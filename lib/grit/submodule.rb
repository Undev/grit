module Grit

  class Submodule
    class MicroSubmodule
      attr_reader :repo, :id, :name, :mode
    end

    # Public: The Grit::Repo instance for submodule repo
    attr_reader :repo

    # Public: The String of name of submodule (relative path inside parent repo)
    attr_reader :name

    # Public: url of submodule remote
    attr_reader :url

    # Public: The String of submodule id
    attr_reader :id

    # Public: The Grit::Repo instance for parent repo
    attr_reader :parent

    # Create submodules for given parent and ref
    #   +parent+ is parent repo of type Grit::Repo
    #   +ref+ is the committish (defaults to 'master')
    # Returns a Hash of { <path:String> => <submodule:Grit::Submodule> }
    # Returns {} if parent doesn't contain submodules
    def self.create_submodules(parent, ref = "master")
      rst = {}
      parent_dir = File.dirname(parent.path)
      submodules_info = self.config(parent, ref)
      submodules_info.each do |name, atts|
        path = File.join(parent_dir, name)
        submodule = Submodule.new(path, name, atts['url'], atts['id'], parent)
        rst[name] = submodule
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
          config[current]['id'] = (commit.tree/current).id
        elsif line =~ /^\t(\w+) = (.+)$/
          config[current][$1] = $2
          config[current]['id'] = (commit.tree/$2).id if $1 == 'path'
        else
          # ignore
        end
      end

      config
    end

    # Initializer for Grit::Submodule
    def initialize(path, name, url, id, parent)
      @repo = Repo.new(path)
      @name = name
      @url = url
      @id = id
      @parent = parent
    end

    # Pretty object inspection
    def inspect
      %Q{#<Grit::Submodule "#{@name}" -- "#{@id}">}
    end
  end # Submodule

end # Grit
