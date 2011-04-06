module Grit

  class Ref

    class << self

      # Find all Refs
      #   +repo+ is the Repo
      #   +options+ is a Hash of options
      #
      # Returns Grit::Ref[] (baked)
      def find_all(repo, options = {})
        refs = repo.git.refs(options, prefix)
        refs.split("\n").map do |ref|
          name, id = *ref.split(' ')
          self.new(name, id, repo)
        end
      end

      protected

        def prefix
          "refs/#{name.to_s.gsub(/^.*::/, '').downcase}s"
        end

      end

      attr_reader :name
      attr_reader :commit

      # Instantiate a new Head
      #   +name+ is the name of the head
      #   +commit+ is the Commit that the head points to
      #
      # Returns Grit::Head (baked)
      def initialize(name, commit, parent)
        @name = name
        @commit = Commit.create(parent, :id => commit)
        @parent = parent
      end

      # Pretty object inspection
      def inspect
        %Q{#<#{self.class.name} "#{@name}">}
      end
    end # Ref

  # A Head is a named reference to a Commit. Every Head instance contains a name
  # and a Commit object.
  #
  #   r = Grit::Repo.new("/path/to/repo")
  #   h = r.heads.first
  #   h.name       # => "master"
  #   h.commit     # => #<Grit::Commit "1c09f116cbc2cb4100fb6935bb162daa4723f455">
  #   h.commit.id  # => "1c09f116cbc2cb4100fb6935bb162daa4723f455"
  class Head < Ref

    # Get the HEAD revision of the repo.
    #   +repo+ is the Repo
    #   +options+ is a Hash of options
    #
    # Returns Grit::Head (baked)
    def self.current(repo, options = {})
      begin
        head_ref = repo.git.symbolic_ref({:q => true}, 'HEAD').chomp
      rescue Git::Errors::CommandFailed => err
        raise  if err.exitstatus != 1
        return nil
      end
      id = repo.git.rev_parse(options, head_ref)
      commit = Commit.create(repo, :id => id)
      (_, _, branch_name) = head_ref.split('/')
      self.new(branch_name, commit)
    end

    def self.create(repo, name, commit='master', opts={})
      commit_id = repo.git.branch(opts, name, commit)
      self.new(name, commit_id, repo)
    end

    def change_ref(new_ref)
      new_commit_id = @parent.git.branch({'force' => true}, @name, new_ref)
      @commit = Commit.create(@parent, :id => new_commit_id)

      true
    end

    def to_s
      @name
    end

  end # Head

  class Remote < Ref; end

  class Note < Ref; end

end # Grit
