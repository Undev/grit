module Grit

  class Status
    include Enumerable

    attr_reader :files

    @base = nil
    @files = nil

    def initialize(base)
      @base = base
      construct_status
    end

    def changed
      @files.select { |k, f| f.type == 'M' }
    end
    alias_method :uncommitted, :changed

    def conflicted
      @files.select { |k, f| f.type == 'U' }
    end
    alias_method :unmerged, :conflicted

    def added
      @files.select { |k, f| f.type == 'A' }
    end

    def deleted
      @files.select { |k, f| f.type == 'D' }
    end

    def untracked
      @files.select { |k, f| f.untracked }
    end

    def modified_names
      changed.keys + added.keys
    end

    def pretty
      out = ''
      self.each do |file|
        out << file.path
        out << "\n\tsha(r) " + file.sha_repo.to_s + ' ' + file.mode_repo.to_s
        out << "\n\tsha(i) " + file.sha_index.to_s + ' ' + file.mode_index.to_s
        out << "\n\ttype   " + file.type.to_s
        out << "\n\tstage  " + file.stage.to_s
        out << "\n\tuntrac " + file.untracked.to_s
        out << "\n"
      end
      out << "\n"
      out
    end

    # enumerable method

    def [](file)
      @files[file]
    end

    def each
      @files.each do |k, file|
        yield file
      end
    end

    class StatusFile
      attr_accessor :path, :type, :stage, :untracked
      attr_accessor :mode_index, :mode_repo
      attr_accessor :sha_index, :sha_repo
      attr_reader :base

      @base = nil

      def initialize(base, hash)
        @base = base
        @path = hash[:path]
        @type = hash[:type]
        @stage = hash[:stage]
        @mode_index = hash[:mode_index]
        @mode_repo = hash[:mode_repo]
        @sha_index = hash[:sha_index]
        @sha_repo = hash[:sha_repo]
        @untracked = hash[:untracked]
      end

      def blob(type = :index)
        if type == :repo
          @base.blob(@sha_repo)
        else
          @base.blob(@sha_index) rescue @base.blob(@sha_repo)
        end
      end

      def raw_data
        File.open(File.join(@base.working_dir, @path), 'r') { |f| f.read }
      end

    end

    private

      def construct_status
        @files = ls_files

        # find untracked in working dir
        ls_files_untracked.each do |file|
          @files[file] = {:path => file, :untracked => true}
        end

        # find modified in tree
        diff_files({:diff_filter => 'M'}).each do |path, data|
          @files[path].merge!(data)
        end

        # find unmerged (conflicted) in tree
        diff_files({:diff_filter => 'U'}).each do |path, data|
          @files[path].merge!(data)
        end

        # find added but not committed - new files
        diff_index('HEAD', {:diff_filter => 'A'}).each do |path, data|
          @files[path].merge!(data)
        end

        @files.each do |k, file_hash|
          @files[k] = StatusFile.new(@base, file_hash)
        end
      end

      # gets locally changed filenames
      def status_files
        @base.git.status(:porcelain => true).split("\n").map {|l| l[3..-1]}
      end

      # compares the index and the working directory
      def diff_files(opts={})
        hsh = {}
        @base.git.diff_files(opts).split("\n").each do |line|
          (info, file) = line.split("\t")
          (mode_src, mode_dest, sha_src, sha_dest, type) = info.split
          hsh[file] = {:path => file, :mode_file => mode_src.to_s[1, 7], :mode_index => mode_dest,
                        :sha_file => sha_src, :sha_index => sha_dest, :type => type}
        end
        hsh
      end

      # compares the index and the repository
      def diff_index(treeish, opts={})
        hsh = {}
        begin
          @base.git.diff_index(opts, treeish).split("\n").each do |line|
            (info, file) = line.split("\t")
            (mode_src, mode_dest, sha_src, sha_dest, type) = info.split
            hsh[file] = {:path => file, :mode_repo => mode_src.to_s[1, 7], :mode_index => mode_dest,
                         :sha_repo => sha_src, :sha_index => sha_dest, :type => type}
          end
        rescue Grit::Errors::CommandFailed
          # prevent fail if repo is empty
          raise if !@base.branches().empty?
        end
        hsh
      end

      def ls_files
        hsh = {}
        lines = @base.git.ls_files({:stage => true})
        lines.split("\n").each do |line|
          # can be dangerous: ls-files may return tag
          # as first, additional column
          (info, file) = line.split("\t")
          (mode, sha, stage) = info.split
          hsh[file] = {:path => file, :mode_index => mode, :sha_index => sha, :stage => stage}
        end
        hsh
      end

      def ls_files_untracked
        @base.git.ls_files({:exclude_standard => true, :others => true}).split
      end
  end

end
