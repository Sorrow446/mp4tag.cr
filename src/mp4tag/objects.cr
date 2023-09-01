module MP4Tag
	class InvalidMagicException < Exception
  end
	class UnsupportedFtypException < Exception
  end
 	class BoxNotPresentException < Exception
  end
	# class EmptyTagsException < Exception
 	# end
	class InvalidStcoSizeException < Exception
  end

	private FTYPS = [
		Bytes[0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20], # M4A
		Bytes[0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x42, 0x20], # M4B
		Bytes[0x66, 0x74, 0x79, 0x70, 0x64, 0x61, 0x73, 0x68], # dash
		Bytes[0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x31], # mp41		
		Bytes[0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32], # mp42
		Bytes[0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D], # isom
		Bytes[0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x32], # iso2
		Bytes[0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x63, 0x31]  # avc1
	]

	# Boxes to expand.
	private CONTAINERS = [
	  "moov", "udta", "meta", "ilst", "----", "(c)alb",
	  "aART", "(c)art", "(c)nam", "(c)cmt", "(c)gen", "gnre",
	  "(c)wrt", "(c)con", "cprt", "desc", "(c)lyr", "(c)nrt",
	  "(c)pub", "trkn", "covr", "(c)day", "disk", "(c)too",
	  "trak", "mdia", "minf", "stbl", "rtng", "plID",
	  "atID", "tmpo", "sonm", "soal", "soar", "soco",
	  "soaa"
	]

	# Pre-defined genres. https://en.wikipedia.org/wiki/List_of_ID3v1_genres
	enum MP4GENRE : UInt8
	  Blues = 1
	  ClassicRock
	  Country
	  Dance
	  Disco
	  Funk
	  Grunge
	  HipHop
	  Jazz
	  Metal
	  NewAge
	  Oldies
	  Other
	  Pop
	  RhythmAndBlues
	  Rap
	  Reggae
	  Rock
	  Techno
	  Industrial
	  Alternative
	  Ska
	  DeathMetal
	  Pranks
	  Soundtrack
	  Eurotechno
	  Ambient
	  TripHop
	  Vocal
	  JassAndFunk
	  Fusion
	  Trance
	  Classical
	  Instrumental
	  Acid
	  House
	  Game
	  SoundClip
	  Gospel
	  Noise
	  AlternativeRock
	  Bass
	  Soul
	  Punk
	  Space
	  Meditative
	  InstrumentalPop
	  InstrumentalRock
	  Ethnic
	  Gothic
	  Darkwave
	  Technoindustrial
	  Electronic
	  PopFolk
	  Eurodance
	  SouthernRock
	  Comedy
	  Cull
	  Gangsta
	  Top40
	  ChristianRap
	  PopSlashFunk
	  JungleMusic
	  NativeUS
	  Cabaret
	  NewWave
	  Psychedelic
	  Rave
	  Showtunes
	  Trailer
	  Lofi
	  Tribal
	  AcidPunk
	  AcidJazz
	  Polka
	  Retro
	  Musical
	  RockNRoll
	  HardRock
	end

	enum ITUNESADVISORY : UInt8
		Explicit = 1
		Clean
	end

	enum IMAGEFORMAT : UInt8
		JPEG = 13
		PNG
		Auto
	end

	class MP4Tags
	  property album : String = ""
	  property album_artist : String = ""
	  property album_artist_sort : String = ""
	  property album_sort : String = ""
	  property artist : String = ""
	  property artist_sort : String = ""
	  property bpm : Int16 = 0
	  property comment : String = ""
	  property composer : String = ""
	  property composer_sort : String = ""
	  property conductor : String = ""
	  property copyright : String = ""  
	  property custom : Hash(String, String)
	  property custom_genre : String = ""
	  property date : String = ""
	  property description : String = ""
	  property director : String = ""
	  property disc_number : Int16 = 0
	  property disc_total : Int16 = 0
	  property genre : MP4GENRE?
	  property itunes_advisory : ITUNESADVISORY?
	  property itunes_album_id : Int32 = 0
	  property itunes_artist_id : Int32 = 0
	  property lyrics : String = ""  
	  property narrator : String = ""
	  property pictures : Array(MP4Picture)
	  property publisher : String = ""
	  property title : String = ""
	  property title_sort : String = ""
	  property track_number : Int16 = 0
	  property track_total : Int16 = 0
	  property year : Int32 = 0

	  def initialize()
	    @custom = Hash(String, String).new
	    @pictures = Array(MP4Picture).new
	  end
	end

	private class MP4Picture
	  property format : IMAGEFORMAT = IMAGEFORMAT::Auto
	  property data   : Bytes = Bytes.new(0)
	end

	private class MP4Box
	  property start_offset : Int64
	  property end_offset   : Int64
	  property box_size     : Int64
	  property path         : String 
	  def initialize(@start_offset, @end_offset, @box_size, @path)
	  end
	end

  private class MP4Boxes
    property boxes : Array(MP4Box)
    def initialize()
      @boxes = Array(MP4Box).new
    end

    def get_box_by_path(path : String) : MP4Box?
      @boxes.each do |b|
        return b if b.path == path
      end
    end

    def get_boxes_by_path(path : String) : Array(MP4Box)
      out_boxes = Array(MP4Box).new
      @boxes.each do |b|
        out_boxes.push(b) if b.path == path
      end
      return out_boxes
    end
  end
end