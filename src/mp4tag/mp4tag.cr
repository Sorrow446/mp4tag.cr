require "file_utils"

module MP4Tag
  BUF_SIZE = 4096*1024

  class MP4
    property io : IO

    protected def close() : Nil
      @io.close
    end

    private def check_header() : Nil
      buf = Bytes.new(8)

      @io.seek(4, IO::Seek::Set)
      @io.read_fully(buf)

      if buf[...4] != Bytes[0x66, 0x74, 0x79, 0x70]
        raise(
          InvalidMagicException.new(
            "file header is corrupted or not an mp4 file"
          )
        )
      end

      if !buf.in?(FTYPS)
        raise(
          UnsupportedFtypException.new(
            "unsupported ftyp: " + String.new(buf[4...])
          )
        )
      end

    end

    def initialize(mp4_path : String)
      @io = File.open(mp4_path, "rb")
      begin
        check_header
      rescue ex
        @io.close
        raise(ex)
      end
      # Can't use @io.size.
      @mp4_path = mp4_path
      @mp4_size = File.size(@mp4_path)
    end

    private def read_box_name() : String
      buf = Bytes.new(4)
      @io.read_fully(buf)
      box_name = String.new(buf)
      if buf[0] == 0xA9
        box_name = "(c)" + box_name[1...].downcase
      end
      return box_name
    end

    private def read_boxes(boxes : MP4Boxes, parent_ends_at = -1, level = 0, p = "")
      cur_pos = @io.pos
      return if cur_pos >= parent_ends_at 

      box_size = @io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
      box_name = read_box_name
      ends_at = cur_pos + box_size
      @io.seek(4, IO::Seek::Current) if box_name == "meta"
      # AtomicParsley-style tree print.
      #puts("#{"    " * level}Atom #{box_name} @ #{cur_pos} of size: #{box_size}, ends @ #{ends_at}")
      p += "." + box_name
      box = MP4Box.new(cur_pos.to_i64, ends_at.to_i64, box_size, p[1...])
      boxes.boxes.push(box)

      if CONTAINERS.any? &.in?(box_name)
        read_boxes(boxes, ends_at, level + 1, p)
      end
      p = p[...-box_name.size-1]
      @io.seek(cur_pos + box_size, IO::Seek::Set)
      read_boxes(boxes, parent_ends_at, level, p)
    end

    private def read_tag(boxes : MP4Boxes, box_name : String) : String
      path = "moov.udta.meta.ilst.#{box_name}.data"
      box = boxes.get_box_by_path(path)
      return "" if box.nil?
      @io.seek(box.start_offset, IO::Seek::Set)
      @io.seek(16, IO::Seek::Current)
      @io.read_string(box.box_size-16)
    end

    private def read_custom(boxes : MP4Boxes) : Hash(String, String)
      h = Hash(String, String).new
      names = Array(String).new
      values = Array(String).new

      path = "moov.udta.meta.ilst.----"
      name_boxes = boxes.get_boxes_by_path(path+".name")
      return h if name_boxes.empty?
      name_boxes.each do |box|
        @io.seek(box.start_offset, IO::Seek::Set)
        @io.seek(12, IO::Seek::Current)
        v = @io.read_string(box.box_size-12)
        names.push(v)
      end

      data_boxes = boxes.get_boxes_by_path(path+".data")
      return h if data_boxes.empty?
      data_boxes.each do |box|
        @io.seek(box.start_offset, IO::Seek::Set)
        @io.seek(16, IO::Seek::Current)
        v = @io.read_string(box.box_size-16)
        values.push(v)
      end

      (0...values.size).each do |idx|
        h[names[idx]] = values[idx]
      end

      return h

    end

    private def read_trkn_disk(boxes : MP4Boxes, box_name = "trkn") : {Int16, Int16}
      box = boxes.get_box_by_path("moov.udta.meta.ilst.#{box_name}.data")
      return {0_i16, 0_i16} if box.nil?
      @io.seek(box.start_offset+18, IO::Seek::Set)
      
      track_num = @io.read_bytes(Int16, IO::ByteFormat::BigEndian)
      track_total = @io.read_bytes(Int16, IO::ByteFormat::BigEndian)

      return track_num, track_total
    end

    private def read_bpm(boxes : MP4Boxes) : Int16
      box = boxes.get_box_by_path("moov.udta.meta.ilst.tmpo.data")
      return 0_i16 if box.nil?
      @io.seek(box.start_offset+16, IO::Seek::Set)
      @io.read_bytes(Int16, IO::ByteFormat::BigEndian)
    end

    private def read_pics(boxes : MP4Boxes) : Array(MP4Picture)
      out_pics = Array(MP4Picture).new
      boxes = boxes.get_boxes_by_path("moov.udta.meta.ilst.covr.data")
      return out_pics if boxes.nil?
      boxes.each do |box|
        pic = MP4Picture.new
        @io.seek(box.start_offset+11, IO::Seek::Set)
        b = @io.read_byte
        raise("unexpected eof") if b.nil?
        if b == IMAGEFORMAT::PNG.value
          pic.format = IMAGEFORMAT::PNG
        else
          pic.format = IMAGEFORMAT::JPEG
        end
        @io.seek(4, IO::Seek::Current)
        buf = Bytes.new(box.box_size-16)
        @io.read_fully(buf)
        pic.data = buf
        out_pics.push(pic)
      end
      return out_pics
    end

    private def read_gnre(boxes : MP4Boxes) : MP4GENRE?
      box = boxes.get_box_by_path("moov.udta.meta.ilst.gnre.data")
      return if box.nil?
      @io.seek(box.start_offset+17, IO::Seek::Set)
      b = @io.read_byte
      raise("unexpected eof") if b.nil?
      gnre = MP4GENRE.new(b)
      return gnre if MP4GENRE.valid?(gnre)
    end

    private def read_advisory(boxes : MP4Boxes) : ITUNESADVISORY?
      box = boxes.get_box_by_path("moov.udta.meta.ilst.rtng.data")
      return if box.nil?
      @io.seek(box.start_offset+16, IO::Seek::Set)
      b = @io.read_byte
      raise("unexpected eof") if b.nil?
      rtng = ITUNESADVISORY.new(b)
      return rtng if ITUNESADVISORY.valid?(rtng)
    end

    private def read_it_album_id(boxes : MP4Boxes) : Int32
      box = boxes.get_box_by_path("moov.udta.meta.ilst.plID.data")
      if box.nil?
        return 0
      end
      @io.seek(box.start_offset+20, IO::Seek::Set)
      @io.read_bytes(Int32, IO::ByteFormat::BigEndian)
    end

    private def read_it_artist_id(boxes : MP4Boxes) : Int32
      box = boxes.get_box_by_path("moov.udta.meta.ilst.atID.data")
      if box.nil?
        return 0
      end
      @io.seek(box.start_offset+16, IO::Seek::Set)
      @io.read_bytes(Int32, IO::ByteFormat::BigEndian)
    end    

    private def read_tags(boxes : MP4Boxes) : MP4Tags
      tags = MP4Tags.new
      return tags if boxes.get_box_by_path("moov.udta.meta.ilst").nil?
      tags.album = read_tag(boxes, "(c)alb")
      tags.album_artist = read_tag(boxes, "aART")
      tags.artist = read_tag(boxes, "(c)art")
      tags.bpm = read_bpm(boxes)
      tags.comment = read_tag(boxes, "(c)cmt")
      tags.composer = read_tag(boxes, "(c)wrt")
      tags.conductor = read_tag(boxes, "(c)con")
      tags.copyright = read_tag(boxes, "cprt")
      tags.custom = read_custom(boxes)
      tags.custom_genre = read_tag(boxes, "(c)gen")
      tags.description = read_tag(boxes, "desc")
      tags.lyrics = read_tag(boxes, "(c)lyr")
      tags.narrator = read_tag(boxes, "(c)nrt")
      tags.publisher = read_tag(boxes, "(c)pub")
      tags.title = read_tag(boxes, "(c)nam")

      tags.itunes_advisory = read_advisory(boxes)
      tags.itunes_album_id = read_it_album_id(boxes)
      tags.itunes_artist_id = read_it_artist_id(boxes)

      trkn = read_trkn_disk(boxes)
      tags.track_number = trkn[0]
      tags.track_total = trkn[1]
      disk = read_trkn_disk(boxes, "disk")
      tags.disc_number = disk[0]
      tags.disc_total = disk[1]     

      tags.pictures = read_pics(boxes)

      year = read_tag(boxes, "(c)day")
      if !year.empty?
        if year.each_char.all? &.number?
          tags.year = year.to_i32
        else
          tags.date = year
        end
      end

      gnre = read_gnre(boxes)
      gnre.try { |gnre| tags.genre = gnre }
      return tags
    end

    private def get_pic_format(format : IMAGEFORMAT, magic : Slice(UInt8)) : UInt8
      if format == IMAGEFORMAT::Auto
        if magic == Bytes[0x89, 0x50, 0x4E, 0x47]
          return 0xE_u8
        end
      end
      if format == IMAGEFORMAT::PNG
        return 0xE_u8
      end
      return 0x0D_u8
    end

    private def write_pics(io : IO, pics : Array(MP4Picture))
      buf = Bytes.new(4)
      pics.each do |p|
        data_size = p.data.size
        next if data_size < 1
        IO::ByteFormat::BigEndian.encode(data_size+24, buf)
        io.write(buf)
        io.print("covr")
        IO::ByteFormat::BigEndian.encode(data_size+16, buf)
        io.write(buf)
        io.print("data")
        format_byte = get_pic_format(p.format, p.data[...4])
        io.write(Bytes[0x0, 0x0, 0x0, format_byte, 0x00, 0x00, 0x00, 0x00])
        io.write(p.data)
      end
    end

    private def read_to_offset(io : IO, start_offset : Int64)
      # Read from src until offset and write to dest.
      @io.seek(0, IO::Seek::Set)
      buf = Bytes.new(BUF_SIZE)
      total_read = 0
      loop do
        read = @io.read(buf)
        if read < 1
          raise("unexpected eof")
        end
        total_read += read
        if total_read > start_offset
          io.write(buf[...start_offset-read])
          break
        end
        io.write(buf)
      end
    end

    private def write_regular(io : IO, box_name : String, val : String, prefix = true)
      # Don't do val.size.
      box_size = val.to_slice.size + 24
      buf = Bytes.new(4)
      IO::ByteFormat::BigEndian.encode(box_size, buf)
      io.write(buf)
      io.write_byte(0xA9) if prefix
      io.print(box_name)
      IO::ByteFormat::BigEndian.encode(box_size-8, buf)
      io.write(buf)
      io.print("data")
      io.write(Bytes[0x0, 0x0, 0x0, 0x01, 0x0, 0x0, 0x0, 0x0])
      io.print(val)
    end

    private def write_gnre(io : IO, genre : UInt8) : Nil
      io.write(Bytes[0x0, 0x0, 0x0, 0x1A])
      io.print("gnre")
      io.write(Bytes[0x0, 0x0, 0x0, 0x12])
      io.print("data")
      io.write(Slice.new(9, 0x0_u8))
      io.write_byte(genre)
    end

    private def write_trkn_disk(io : IO, num : Int16, total : Int16, box_name = "trkn") : Nil
      num = 0 if num < 0
      total = 0 if num < 0
      buf = Bytes.new(4)
      box_size = 30
      box_size += 2 if box_name == "trkn"
      IO::ByteFormat::BigEndian.encode(box_size, buf)
      io.write(buf)
      io.print(box_name)
      IO::ByteFormat::BigEndian.encode(box_size-8, buf)
      io.write(buf)
      io.print("data")
      io.write(Slice.new(10, 0x0_u8))
      buf = Bytes.new(2)
      IO::ByteFormat::BigEndian.encode(num, buf)
      io.write(buf)
      IO::ByteFormat::BigEndian.encode(total, buf)
      io.write(buf)
      io.write(Slice.new(2, 0x0_u8)) if box_name == "trkn"
    end

     private def write_bpm(io : IO, bpm : Int16) : Nil
      buf = Bytes.new(2)
      io.write(Bytes[0x0, 0x0, 0x0, 0x1A])
      io.print("tmpo")
      io.write(Bytes[0x0, 0x0, 0x0, 0x12])
      io.print("data")
      io.write(Bytes[0x0, 0x0, 0x0, 0x15, 0x0, 0x0, 0x0, 0x0])
      IO::ByteFormat::BigEndian.encode(bpm, buf)
      io.write(buf)
    end

    private def write_advisory(io : IO, advisory : UInt8) : Nil
      io.write(Bytes[0x0, 0x0 ,0x0, 0x19])
      io.print("rtng")
      io.write(Bytes[0x0, 0x0 ,0x0, 0x11])
      io.print("data")
      io.write(Bytes[0x0, 0x0, 0x0, 0x15, 0x0, 0x0, 0x0, 0x0])
      io.write_byte(advisory)
    end

    private def write_custom(io : IO, k : String, v : String) : Nil
      k_size = k.to_slice.size
      v_size = v.to_slice.size
      buf = Bytes.new(4)
      IO::ByteFormat::BigEndian.encode(k_size + v_size + 64 , buf)
      io.write(buf)
      io.print("----")
      IO::ByteFormat::BigEndian.encode(28, buf)
      io.write(buf)
      io.print("mean")
      io.write(Slice.new(4, 0x0_u8))
      io.print("com.apple.iTunes")
      IO::ByteFormat::BigEndian.encode(k_size+12, buf)
      io.write(buf)
      io.print("name")
      io.write(Slice.new(4, 0x0_u8))
      io.print(k.upcase)
      IO::ByteFormat::BigEndian.encode(v_size+16, buf)
      io.write(buf)
      io.print("data")
      io.write(Bytes[0x0, 0x0, 0x0, 0x01, 0x0, 0x0, 0x0, 0x0])
      io.print(v)
    end    

    private def update_chunk_offsets(io : IO, boxes : MP4Boxes, old_ilst_size : Int64, new_ilst_size : Int64)
      buf = Bytes.new(4)
      stco = boxes.get_box_by_path("moov.trak.mdia.minf.stbl.stco")
      return if stco.nil?

      @io.seek(stco.start_offset+12, IO::Seek::Set)
      io.seek(stco.start_offset+16, :set)

      count = @io.read_bytes(UInt32, IO::ByteFormat::BigEndian)

      if stco.box_size != count * 4 + 16
        raise(InvalidStcoSizeException.new("bad stco box size"))
      end

      count.times do
        offset = @io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
        IO::ByteFormat::BigEndian.encode(offset - old_ilst_size + new_ilst_size, buf)
        io.write(buf)
      end
    end

    private def resize_boxes(io : IO, boxes : MP4Boxes, old_ilst_size : Int64, new_ilst_size : Int64)
      moov = boxes.get_box_by_path("moov")
      return if moov.nil?

      udta = boxes.get_box_by_path("moov.udta")
      return if udta.nil?

      meta = boxes.get_box_by_path("moov.udta.meta")
      return if meta.nil?

      buf = Bytes.new(4)

      IO::ByteFormat::BigEndian.encode(new_ilst_size.to_i32, buf)
      io.write(buf)

      io.seek(moov.start_offset, :set)
      new_moov_size = moov.box_size - old_ilst_size + new_ilst_size
      IO::ByteFormat::BigEndian.encode(new_moov_size.to_i32, buf)
      io.write(buf)

      io.seek(udta.start_offset, :set)
      new_udta_size = udta.box_size - old_ilst_size + new_ilst_size
      IO::ByteFormat::BigEndian.encode(new_udta_size.to_i32, buf)
      io.write(buf)

      io.seek(meta.start_offset, :set)
      new_meta_size = meta.box_size - old_ilst_size + new_ilst_size
      IO::ByteFormat::BigEndian.encode(new_meta_size.to_i32, buf)
      io.write(buf)
    end

    private def write_remaining(io : IO) : Nil
      buf = Bytes.new(BUF_SIZE)
      loop do
        read = @io.read(buf)
        if read < 1
          break
        elsif read < BUF_SIZE
          io.write(buf[...read])
          break
        else
          io.write(buf)
        end      
      end
    end

    # private def write_new_udta(io  : IO, boxes : MP4Boxes) : Nil
    #   udta_start_offset = io.pos
    #   io.write(Slice.new(4, 0x0_u8))
    #   io.print("udta")

    #   meta_start_offset = io.pos
    #   io.write(Slice.new(4, 0x0_u8))
    #   io.print("meta")


    #   hdlr_start_offset = io.pos
    #   io.write(Slice.new(8, 0x0_u8))
    #   io.print("hdlr")
    #   io.write(Slice.new(8, 0x0_u8))
    #   io.print("mdirappl")
    #   io.write(Slice.new(9, 0x0_u8))
    #   udta_end_offset = io.pos

    #   udta = MP4Box.new(
    #     udta_start_offset, udta_end_offset, udta_end_offset-udta_start_offset, "moov.udta")
    #   meta = MP4Box.new(
    #     meta_start_offset, hdlr_start_offset, hdlr_start_offset-meta_start_offset, "moov.udta.meta")
    #   hdlr = MP4Box.new(
    #    hdlr_start_offset, udta_end_offset, udta_end_offset-hdlr_start_offset, "moov.udta.meta.hdlr")
    #   ilst = MP4Box.new(
    #    udta_end_offset, udta_end_offset+8, 8, "moov.udta.meta.ilst")

    #   boxes.boxes.push(udta)
    #   boxes.boxes.push(meta)
    #   boxes.boxes.push(hdlr)
    #   boxes.boxes.push(ilst)
    # end

    private def check_boxes(boxes : MP4Boxes) : Nil
      paths = [
        "moov", "mdat", "moov.udta", "moov.udta.meta",
        "moov.trak.mdia.minf.stbl.stco"
      ]

      paths.each do |p|
        if boxes.get_box_by_path(p).nil?
          raise(
            BoxNotPresentException.new(p + " box not present")
          )
        end
      end
    end

    private def write_it_album_id(io : IO, album_id : Int32) : Nil
      buf = Bytes.new(4)
      io.write(Bytes[0x0, 0x0, 0x0, 0x20])
      io.print("plID")
      io.write(Bytes[0x0, 0x0, 0x0, 0x18])
      io.print("data")
      io.write(Bytes[0x0, 0x0, 0x0, 0x15, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0])
      IO::ByteFormat::BigEndian.encode(album_id, buf)
      io.write(buf)
    end

    private def write_it_artist_id(io : IO, artist_id : Int32) : Nil
      buf = Bytes.new(4)
      io.write(Bytes[0x0, 0x0, 0x0, 0x1C])
      io.print("atID")
      io.write(Bytes[0x0, 0x0, 0x0, 0x14])
      io.print("data")
      io.write(Bytes[0x0, 0x0, 0x0, 0x15, 0x0, 0x0, 0x0, 0x0])
      IO::ByteFormat::BigEndian.encode(artist_id, buf)
      io.write(buf)
    end    

    private def write_tags(boxes : MP4Boxes, tags : MP4Tags, temp_path : String) : Nil
      ilst = boxes.get_box_by_path("moov.udta.meta.ilst")
      return if ilst.nil?
      old_ilst_size = ilst.box_size

      File.open(temp_path, "wb") do |f|

        read_to_offset(f, ilst.start_offset)
        ilst_start_offset = f.pos

        f.write(Slice.new(4, 0x0_u8))
        f.print("ilst")

        write_regular(f, "nam", tags.title) if !tags.title.empty?
        write_regular(f, "sonm", tags.title_sort, false) if !tags.title_sort.empty?
        write_regular(f, "alb", tags.album) if !tags.album.empty?
        write_regular(f, "soal", tags.album_sort, false) if !tags.album_sort.empty?
        write_regular(f, "aART", tags.album_artist, false) if !tags.album_artist.empty?
        write_regular(f, "soaa", tags.album_artist_sort, false) if !tags.album_artist_sort.empty?
        write_regular(f, "ART", tags.artist) if !tags.artist.empty?
        write_regular(f, "soar", tags.artist_sort, false) if !tags.artist_sort.empty?
        write_regular(f, "cmt", tags.comment) if !tags.comment.empty?
        write_regular(f, "wrt", tags.composer) if !tags.composer.empty?
        write_regular(f, "soco", tags.composer_sort, false) if !tags.composer_sort.empty?
        write_regular(f, "cprt", tags.copyright, false) if !tags.copyright.empty?
        write_regular(f, "lyr", tags.lyrics) if !tags.lyrics.empty?
        write_regular(f, "gen", tags.custom_genre) if !tags.custom_genre.empty?
        write_regular(f, "desc", tags.description, false) if !tags.description.empty?
        write_regular(f, "pub", tags.publisher) if !tags.publisher.empty?
        write_regular(f, "con", tags.conductor) if !tags.conductor.empty?
        
        write_bpm(f, tags.bpm) if tags.bpm > 0

        if tags.year > 0
          write_regular(f, "day", tags.year.to_s)
        elsif !tags.date.empty?
          write_regular(f, "day", tags.date)
        end
        tags.itunes_advisory.try { |a| write_advisory(f, a.value) }
        if tags.track_number > 0 || tags.track_total > 0
          write_trkn_disk(f, tags.track_number, tags.track_total)
        end

        write_it_album_id(f, tags.itunes_album_id) if tags.itunes_album_id > 0
        write_it_artist_id(f, tags.itunes_artist_id) if tags.itunes_artist_id > 0


        if tags.disc_number > 0 || tags.disc_total > 0
          write_trkn_disk(f, tags.disc_number, tags.disc_total, "disk")
        end
        
        tags.genre.try { |g| write_gnre(f, g.value) }

        tags.custom.each do |k, v|
          write_custom(f, k, v)
        end

        write_pics(f, tags.pictures) if tags.pictures.size > 0
        # @io.seek(ilst.end_offset, IO::Seek::Set)
        new_ilst_end_offset = f.pos
        new_ilst_size = new_ilst_end_offset - ilst_start_offset
        f.seek(ilst_start_offset, :set)
        resize_boxes(f, boxes, old_ilst_size, new_ilst_size)
        mdat = boxes.get_box_by_path("mdat")
        mdat.try{ |mdat|
          # Don't update offsets if mdat is before ilst.
          if mdat.start_offset > ilst_start_offset && old_ilst_size != new_ilst_size
            update_chunk_offsets(f, boxes, old_ilst_size, new_ilst_size)
          end
        }

        f.seek(new_ilst_end_offset, :set)
        @io.seek(ilst.end_offset, IO::Seek::Set)
        write_remaining(f)
      end
    end

    private def overwrite_tags(merged_tags : MP4Tags, tags : MP4Tags, del_strings : Array(String)) : Nil
      if "all_tags".in?(del_strings)
        merged_pics = merged_tags.pictures
        merged_tags = MP4Tags.new
        merged_tags.pictures = merged_pics
      elsif "all_custom".in?(del_strings)
        merged_tags.custom = Hash(String, String).new
      end

      merged_tags.album = "" if "album".in?(del_strings)
      merged_tags.album_artist = "" if "album_artist".in?(del_strings)
      merged_tags.album_artist_sort = "" if "album_artist_sort".in?(del_strings)
      merged_tags.album_sort = "" if "album_sort".in?(del_strings)
      merged_tags.artist = "" if "artist".in?(del_strings)
      merged_tags.artist_sort = "" if "artist_sort".in?(del_strings)
      merged_tags.bpm = 0 if "bpm".in?(del_strings)
      merged_tags.comment = "" if "comment".in?(del_strings)
      merged_tags.composer = "" if "composer".in?(del_strings)
      merged_tags.composer_sort = "" if "composer_sort".in?(del_strings)
      merged_tags.conductor = "" if "conductor".in?(del_strings)
      merged_tags.copyright = "" if "copyright".in?(del_strings)
      merged_tags.custom_genre = "" if "custom_genre".in?(del_strings)
      merged_tags.date = "" if "date".in?(del_strings)
      merged_tags.description = "" if "description".in?(del_strings)
      merged_tags.director = "" if "director".in?(del_strings)
      merged_tags.disc_number = 0 if ["disc_number", "disk_number"].any?(&.in?(del_strings))
      merged_tags.disc_total = 0 if ["disc_total", "disk_total"].any?(&.in?(del_strings)) 
      merged_tags.genre = nil if "genre".in?(del_strings)
      merged_tags.itunes_advisory = nil if "itunes_advisory".in?(del_strings)
      merged_tags.itunes_album_id = 0 if "itunes_album_id".in?(del_strings)
      merged_tags.itunes_artist_id = 0 if "itunes_artist_id".in?(del_strings)
      merged_tags.lyrics = "" if "lyrics".in?(del_strings)
      merged_tags.narrator = "" if "narrator".in?(del_strings)
      merged_tags.publisher = "" if "publisher".in?(del_strings)      
      merged_tags.title = "" if "title".in?(del_strings)
      merged_tags.title_sort = "" if "title_sort".in?(del_strings)
      merged_tags.track_number = 0 if "track_number".in?(del_strings)
      merged_tags.track_total = 0 if "track_total".in?(del_strings)
      merged_tags.year = 0 if "year".in?(del_strings)

      if "all_pictures".in?(del_strings)
        merged_tags.pictures = Array(MP4Picture).new
      end

      merged_tags.album = tags.album if !tags.album.empty?
      merged_tags.album_sort = tags.album_sort if !tags.album_sort.empty?
      merged_tags.album_artist = tags.album_artist if !tags.album_artist.empty?
      merged_tags.album_artist_sort = tags.album_artist_sort if !tags.album_artist_sort.empty?
      merged_tags.artist = tags.artist if !tags.artist.empty?
      merged_tags.artist_sort = tags.artist_sort if !tags.artist_sort.empty?
      merged_tags.bpm = tags.bpm if tags.bpm > 0
      merged_tags.comment = tags.comment if !tags.comment.empty?
      merged_tags.composer = tags.composer if !tags.composer.empty?
      merged_tags.composer_sort = tags.composer_sort if !tags.composer_sort.empty?
      merged_tags.conductor = tags.conductor if !tags.conductor.empty?
      merged_tags.copyright = tags.copyright if !tags.copyright.empty?
      merged_tags.custom_genre = tags.custom_genre if !tags.custom_genre.empty? 
      merged_tags.date = tags.date if !tags.date.empty?
      merged_tags.description = tags.description if !tags.description.empty?
      merged_tags.director = tags.director if !tags.director.empty?
      merged_tags.disc_number = tags.disc_number if tags.disc_number > 0
      merged_tags.disc_total = tags.disc_total if tags.disc_total > 0
      merged_tags.itunes_album_id = tags.itunes_album_id if tags.itunes_album_id > 0
      merged_tags.itunes_artist_id = tags.itunes_artist_id if tags.itunes_artist_id > 0
      merged_tags.lyrics = tags.lyrics if !tags.lyrics.empty? 
      merged_tags.narrator = tags.narrator if !tags.narrator.empty? 
      merged_tags.publisher = tags.publisher if !tags.publisher.empty?
      merged_tags.title = tags.title if !tags.title.empty?
      merged_tags.title_sort = tags.title_sort if !tags.title_sort.empty?
      merged_tags.track_number = tags.track_number if tags.track_number > 0
      merged_tags.track_total = tags.track_total if tags.track_total > 0
      merged_tags.year = tags.year if tags.year > 0

      tags.genre.try { |g|
        if MP4GENRE.valid?(MP4GENRE.new(g.value))
          merged_tags.genre = g
        end
      }

      tags.itunes_advisory.try { |a|
        if ITUNESADVISORY.valid?(ITUNESADVISORY.new(a.value))
          merged_tags.itunes_advisory = a
        end
      }
      
      tags.custom.each do |k, v|
        merged_tags.custom[k] = v if !v.empty?
      end

      filtered_pics = Array(MP4Picture).new

      merged_tags.pictures.each_with_index(1) do |p, idx|
        if !"picture:#{idx}".in?(del_strings)
          filtered_pics.push(p)
        end
      end

      tags.pictures.each do |p|
        filtered_pics.push(p)
      end

      merged_tags.pictures = filtered_pics
    end

    private def get_temp_path() : String
      fname = File.basename(@mp4_path)
      unix = Time.local.to_unix_ns
      File.join(Dir.tempdir, "#{fname}_tmp_#{unix}")
    end

    def read() : MP4Tags
      boxes = MP4Boxes.new
      @io.seek(0, IO::Seek::Set)
      read_boxes(boxes, @mp4_size)
      check_boxes(boxes)
      read_tags(boxes)
    end

    def write(tags : MP4Tags, del_strings = Array(String).new) : Nil
      del_strings.map!(&.downcase)
      boxes = MP4Boxes.new
      @io.seek(0, IO::Seek::Set)
      read_boxes(boxes, @mp4_size)
      check_boxes(boxes)
      merged_tags = read_tags(boxes)
      # if merged_tags.empty?
      #   raise(
      #     EmptyTagsException.new("merged tags are empty, nothing to write")
      #   )
      # end
      overwrite_tags(merged_tags, tags, del_strings)
      temp_path = get_temp_path
      write_tags(boxes, merged_tags, temp_path) 
      @io.close
      FileUtils.rm(@mp4_path)
      # mv not working between different hard drives.
      FileUtils.cp(temp_path, @mp4_path)
      FileUtils.rm(temp_path)
      @io = File.open(@mp4_path, "rb")
      @mp4_size = File.size(@mp4_path)
    end

  end
end