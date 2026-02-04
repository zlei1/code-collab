module OT
  class WrappedOperation
    attr_reader :wrapped, :meta

    def initialize(operation, meta)
      @wrapped = operation
      @meta = meta
    end

    def apply(*args)
      @wrapped.apply(*args)
    end

    def invert(*args)
      meta = @meta
      inverted_meta =
        if meta.is_a?(Object) && meta.respond_to?(:invert)
          meta.invert(*args)
        else
          meta
        end
      self.class.new(@wrapped.invert(*args), inverted_meta)
    end

    def compose(other)
      self.class.new(@wrapped.compose(other.wrapped), compose_meta(@meta, other.meta))
    end

    def self.transform(a, b)
      pair = a.wrapped.class.transform(a.wrapped, b.wrapped)
      [
        new(pair[0], transform_meta(a.meta, b.wrapped)),
        new(pair[1], transform_meta(b.meta, a.wrapped))
      ]
    end

    private

    def compose_meta(a, b)
      if a.is_a?(Object)
        return a.compose(b) if a.respond_to?(:compose)
        meta = {}
        copy_hash(a, meta)
        copy_hash(b, meta)
        return meta
      end
      b
    end

    def copy_hash(source, target)
      return unless source.is_a?(Hash)
      source.each { |key, value| target[key] = value }
    end

    def self.transform_meta(meta, operation)
      if meta.is_a?(Object) && meta.respond_to?(:transform)
        meta.transform(operation)
      else
        meta
      end
    end
  end
end
