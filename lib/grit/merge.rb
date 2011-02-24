module Grit

  class Merge

    STATUS_BOTH = 'both'
    STATUS_OURS = 'ours'
    STATUS_THEIRS = 'theirs'

    attr_reader :conflicts, :text, :sections

    def initialize(str)
      status = STATUS_BOTH

      section = 1
      @conflicts = 0
      @text = {}

      lines = str.split("\n")
      lines.each do |line|
        if /^<<<<<<< (.*?)/.match(line)
          status = STATUS_OURS
          @conflicts += 1
          section += 1
        elsif line == '======='
          status = STATUS_THEIRS
        elsif /^>>>>>>> (.*?)/.match(line)
          status = STATUS_BOTH
          section += 1
        else
          @text[section] ||= {}
          @text[section][status] ||= []
          @text[section][status] << line
        end
      end
      @text = @text.values
      @sections = @text.size
    end

    # Pretty object inspection
    def inspect
      %Q{#<Grit::#{self.class.name}}
    end
  end # Merge

  class ConflictedFile < Merge
    attr_reader :base, :path

    # Creates ConflictedFile object from Status::StatusFile
    def self.create_from_file(st_file)
      self.new(st_file.base, st_file.path, st_file.raw_data)
    end

    def initialize(base, path, str)
      super(str)
      @base = base
      @path = path
    end

    def write_content(text)
      File.open(@path, "w") { |f| f.write(text) }
    end

    # Resolves conflict -- add file to staged area
    def resolve
      @base.add(@path)
    end

  end

end # Grit
