module Grit

  class BaseTreeEntry
    # Generic Tree Entry, base class for Tree, Blob, etc.
    attr_reader :id
    attr_reader :mode
    attr_reader :name

    # Create an unbaked BaseTreeEntry containing just the specified attributes
    #   +repo+ is the Repo
    #   +atts+ is a Hash of instance variable data
    #
    # Returns Grit::BaseTreeEntry (unbaked)
    def self.create(repo, atts)
      self.allocate.create_initialize(repo, atts)
    end

    # Initializer for BaseTreeEntry.create
    #   +repo+ is the Repo
    #   +atts+ is a Hash of instance variable data
    #
    # Returns Grit::BaseTreeEntry (unbaked)
    def create_initialize(repo, atts)
      @repo = repo
      atts.each do |k, v|
        instance_variable_set("@#{k}".to_sym, v)
      end
      self
    end

    def basename
      File.basename(name)
    end

    # Pretty object inspection
    def inspect
      %Q{#<#{self.class.name} "#{@id}">}
    end

    # Compares blobs by name
    def <=>(other)
      name <=> other.name
    end
  end # BaseTreeEntry

end # Grit
