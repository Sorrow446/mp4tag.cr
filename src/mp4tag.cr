require "./mp4tag/*"

module MP4Tag
  def self.open(path : String) : Nil
    mp4 = MP4Tag::MP4.new(path)
    yield mp4 ensure mp4.close
  end
end