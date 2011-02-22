# -*- coding: utf-8 -*-
module Grit

  class Submodule
    # Public: The Grit::Repo instance for submodule repo
    attr_reader :repo

    # Public: The String of path of submodule (relative path inside parent repo)
    attr_reader :path

    # Public: url of submodule remote
    attr_reader :url

    # Public: The Grit::Repo instance for parent repo
    attr_reader :parent

    # Create submodules for given parent and ref
    #   +parent+ is parent repo of type Grit::Repo
    #   +ref+ is the committish (defaults to 'master')
    # Returns a Hash of { <path:String> => <submodule:Grit::Submodule> }
    # Returns {} if parent doesn't contain submodules
    def self.create_submodules(parent, ref = "master")
      rst = {}
      submodules_info = self.config(parent, ref)
      submodules_info.each do |path, atts|
        subm = Submodule.new(path, atts['url'], parent)
        rst[path] = subm
      end

      rst
    end

    # The configuration information for the given +repo+
    #   +repo+ is the Repo
    #   +ref+ is the committish (defaults to 'master')
    #
    # Returns a Hash of { <path:String> => { 'url' => <url:String>, 'id' => <id:String> } }
    # Returns {} if no .gitmodules file was found
    def self.config(repo, ref = "master")
      commit = repo.commit(ref)
      blob = commit.tree/'.gitmodules'
      return {} unless blob

      lines = blob.data.gsub(/\r\n?/, "\n" ).split("\n")

      config = {}
      current = nil

      lines.each do |line|
        if line =~ /^\[submodule "(.+)"\]$/
          current = $1
          config[current] = {}
        elsif line =~ /^\t(\w+) = (.+)$/
          config[current][$1] = $2
        else
          # ignore
        end
      end

      config
    end

    # Entry point for other commands
    def self.submodule(parent, options={}, *args)
      parent.git.submodule(options, *args)
    end

    def self.add(parent, url, path='')
      submodule(parent, {}, 'add', url, path)
      if path == ''
        (path, _) = self.paths.find do |p|
          !parent.submodules.has_key?(p) && url.include?(p)
        end
      end
      subm = Submodule.new(path, url, parent)

      subm
    end

    def self.paths(parent)
      lines = submodule(parent, {}, "status")
      lines.split("\n").map do |line|
        (_, path, _) = line.split(" ")
        path
      end
    end

    # Initializer for Grit::Submodule
    # path   - relative path within parent's working dir
    # url    - url of submodule
    # parent - Grit::Repo instance of parent repo
    def initialize(path, url, parent)
      full_path = File.join(parent.working_dir, path)
      @repo = Repo.new(full_path)
      @path = path
      @url = url
      @parent = parent
    end

    def submodule(options, *args)
      self.class.submodule(@parent, options, *args, @path)
    end

    # Returns parsed result of git submodule status @path command
    # Hash with keys:
    # :initialized? -- indicates whether submodule was initialized
    # :matches? -- shows whether the currently checked out submodule commit
    #              match the SHA-1 found in the index of the parent repository
    # :commit -- currently checked out commit
    # :ref -- ref of checked commit
    def status
      {
        :initialized? => initialized?,
        :matches? => commit_matches?,
        :commit => commit,
        :ref => ref
      }
    end

    def init
      submodule({}, "init")
    end

    # Runs git submodule update @path
    # Options:
    # :init -- perform initialization too
    def update(opts)
      init = opts[:init]
      submodule({:init => init}, "update")
    end

    def commit_sha
      status_line = raw_status().split("\n")[0]
      # not initialized subm don't have ref
      state_n_commit = status_line.split(" ")[0]
      state_n_commit[1..-1] # first char is subm state
    end

    def initialized?
      raw_status()[0] != '-'
    end

    def commit_matches?
      if initialized?
        raw_status()[0] != '+'
      else
        nil
      end
    end

    def ref
      raw_status().split("\n")[0].split(" ")[2]
    end

    def has_file?(file)
      file.start_with?(@path)
    end

    # Pretty object inspection
    def inspect
      %Q{#<Grit::Submodule "#{@path}" -- "#{@url}">}
    end

    private

    def raw_status
      submodule({}, "status")
    end

  end # Submodule

end # Grit
