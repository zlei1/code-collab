module OT
  class Selection
    class Range
      attr_reader :anchor, :head

      def initialize(anchor, head)
        @anchor = anchor
        @head = head
      end

      def self.from_json(obj)
        new(obj["anchor"] || obj[:anchor], obj["head"] || obj[:head])
      end

      def empty?
        @anchor == @head
      end

      def equals?(other)
        @anchor == other.anchor && @head == other.head
      end

      def transform(other)
        transform_index = lambda do |index|
          new_index = index
          other.ops.each do |op|
            if TextOperation.retain?(op)
              index -= op
            elsif TextOperation.insert?(op)
              new_index += op.length
            else
              new_index -= [ index, -op ].min
              index += op
            end
            break if index.negative?
          end
          new_index
        end

        new_anchor = transform_index.call(@anchor)
        if @anchor == @head
          return self.class.new(new_anchor, new_anchor)
        end
        self.class.new(new_anchor, transform_index.call(@head))
      end

      def as_json(*)
        { anchor: @anchor, head: @head }
      end
    end

    attr_reader :ranges

    def initialize(ranges = [])
      @ranges = ranges
    end

    def self.create_cursor(position)
      new([ Range.new(position, position) ])
    end

    def self.from_json(obj)
      obj_ranges = obj.is_a?(Hash) ? (obj["ranges"] || obj[:ranges]) : obj
      ranges = (obj_ranges || []).map { |range| Range.from_json(range) }
      new(ranges)
    end

    def equals?(other)
      return false unless other.is_a?(Selection)
      return false unless @ranges.length == other.ranges.length
      @ranges.each_with_index do |range, idx|
        return false unless range.equals?(other.ranges[idx])
      end
      true
    end

    def something_selected?
      @ranges.any? { |range| !range.empty? }
    end

    def compose(other)
      other
    end

    def transform(other)
      new_ranges = @ranges.map { |range| range.transform(other) }
      self.class.new(new_ranges)
    end

    def as_json(*)
      { ranges: @ranges.map(&:as_json) }
    end
  end
end
