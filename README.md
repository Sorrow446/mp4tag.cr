# mp4tag.cr
MP4 tag library written in Crystal.

## Installation
Add this to your application's shard.yml:
```yaml
dependencies:
  mp4tag:
    github: Sorrow446/mp4tag.cr
```

## Usage
```crystal
require "mp4tag"
```
Opening and exception handling are omitted from the examples.
```crystal
MP4Tag.open("1.m4a") do |mp4|
  # Stuff.
end
```
Read album name:
```crystal
tags = mp4.read
puts(tags.album)
```

Write title and year:
```crystal
tags = MP4Tag::MP4Tags.new
tags.title = "my title"
tags.year = 2023
mp4.write(tags)
```

Extract all pictures:
```crystal
tags = mp4.read
tags.pictures.each_with_index(1) do |p, idx|
  File.write(idx.to_s + ".jpg", p.data)
end
```

Write two covers, retaining any already written:
```crystal
def read_pic_data(pic_path : String) : Bytes
  File.open(pic_path, "rb") do |f|
    f.getb_to_end
  end
end

tags = MP4Tag::MP4Tags.new

pic_data = read_pic_data("1.jpg")
pic = MP4Tag::MP4Image.new
pic.data = pic_data

pic_two_data = read_pic_data("2.jpg")
pic_two = MP4Tag::MP4Image.new
pic_two.data = pic_two_data

tags.pictures.push(pic)
tags.pictures.push(pic_two)
mp4.write(tags)
```

Delete all tags and the second picture:
```crystal
tags = MP4Tag::MP4Image.new
mp4.write(tags, ["all_tags", "picture:2"])
```

## Deletion strings
```
album
album_artist
album_artist_sort
album_sort
all_custom_tags
all_pictures
all_tags
artist
artist_sort
bpm
comment
composer
composer_sort
conductor
copyright
custom_genre
date
description
dis(c/k)_number
dis(c/k)_total
genre
itunes_advisory
itunes_album_id
itunes_artist_id
lyrics
narrator
picture:(index starting from 1)
publisher
title
title_sort
track_number
track_total
year
```
Case-insensitive. Any others will be assumed to be custom tags.

## Objects
```crystal
class InvalidMagicException < Exception
end
class UnsupportedFtypException < Exception
end
class BoxNotPresentException < Exception
end
class InvalidStcoSizeException < Exception
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
end

class MP4Picture
  property format : IMAGEFORMAT = IMAGEFORMAT::Auto
  property data   : Bytes = Bytes.new(0)
end

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
```

## Thank you
- npn from the Crystal Discord server for help parsing MP4 boxes.

