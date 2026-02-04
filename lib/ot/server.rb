module OT
  class Server
    class StaleRevision < StandardError; end

    attr_reader :document, :operations, :base_revision

    def initialize(document, operations = [], base_revision = 0)
      @document = document
      @operations = operations
      @base_revision = base_revision
    end

    def revision
      @base_revision + @operations.length
    end

    def receive_operation(revision, operation)
      if revision < @base_revision
        raise StaleRevision, "operation revision too old"
      end

      if revision > self.revision
        raise ArgumentError, "operation revision not in history"
      end

      index = revision - @base_revision
      concurrent_operations = @operations.slice(index, @operations.length - index) || []
      concurrent_operations.each do |concurrent|
        operation = operation.class.transform(operation, concurrent)[0]
      end

      @document = operation.apply(@document)
      @operations << operation
      operation
    end

    def compact!(max_history)
      return false if max_history <= 0 || @operations.length <= max_history

      @base_revision = revision
      @operations = []
      true
    end
  end
end
