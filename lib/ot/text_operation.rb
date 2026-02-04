module OT
  class TextOperation
    attr_reader :ops, :base_length, :target_length

    def initialize
      @ops = []
      @base_length = 0
      @target_length = 0
    end

    def self.retain?(op)
      op.is_a?(Numeric) && op.positive?
    end

    def self.insert?(op)
      op.is_a?(String)
    end

    def self.delete?(op)
      op.is_a?(Numeric) && op.negative?
    end

    def retain(n)
      raise ArgumentError, "retain expects an integer" unless n.is_a?(Numeric)
      return self if n.zero?

      @base_length += n
      @target_length += n
      if self.class.retain?(@ops.last)
        @ops[-1] += n
      else
        @ops << n
      end
      self
    end

    def insert(str)
      raise ArgumentError, "insert expects a string" unless str.is_a?(String)
      return self if str.empty?

      @target_length += str.length
      if self.class.insert?(@ops.last)
        @ops[-1] += str
      elsif self.class.delete?(@ops.last)
        if self.class.insert?(@ops[-2])
          @ops[-2] += str
        else
          @ops[-1], @ops[-2] = @ops[-2], str
        end
      else
        @ops << str
      end
      self
    end

    def delete(n)
      n = n.length if n.is_a?(String)
      raise ArgumentError, "delete expects an integer or a string" unless n.is_a?(Numeric)
      return self if n.zero?

      n = -n if n.positive?
      @base_length -= n
      if self.class.delete?(@ops.last)
        @ops[-1] += n
      else
        @ops << n
      end
      self
    end

    def noop?
      @ops.empty? || (@ops.length == 1 && self.class.retain?(@ops[0]))
    end

    def to_s
      @ops.map do |op|
        if self.class.retain?(op)
          "retain #{op}"
        elsif self.class.insert?(op)
          "insert '#{op}'"
        else
          "delete #{-op}"
        end
      end.join(", ")
    end

    def as_json(*)
      @ops
    end

    def self.from_json(ops)
      operation = new
      ops.each do |op|
        if retain?(op)
          operation.retain(op)
        elsif insert?(op)
          operation.insert(op)
        elsif delete?(op)
          operation.delete(op)
        else
          raise ArgumentError, "unknown operation: #{op.inspect}"
        end
      end
      operation
    end

    def apply(str)
      raise ArgumentError, "The operation's base length must be equal to the string's length." if str.length != @base_length

      new_str = []
      str_index = 0
      @ops.each do |op|
        if self.class.retain?(op)
          raise ArgumentError, "Operation can't retain more characters than are left in the string." if str_index + op > str.length
          new_str << str.slice(str_index, op)
          str_index += op
        elsif self.class.insert?(op)
          new_str << op
        else
          str_index -= op
        end
      end

      raise ArgumentError, "The operation didn't operate on the whole string." if str_index != str.length
      new_str.join
    end

    def invert(str)
      str_index = 0
      inverse = self.class.new
      @ops.each do |op|
        if self.class.retain?(op)
          inverse.retain(op)
          str_index += op
        elsif self.class.insert?(op)
          inverse.delete(op.length)
        else
          inverse.insert(str.slice(str_index, -op))
          str_index -= op
        end
      end
      inverse
    end

    def compose(operation2)
      operation1 = self
      if operation1.target_length != operation2.base_length
        raise ArgumentError, "The base length of the second operation has to be the target length of the first operation"
      end

      operation = self.class.new
      ops1 = operation1.ops
      ops2 = operation2.ops
      i1 = 0
      i2 = 0
      op1 = ops1[i1]
      i1 += 1
      op2 = ops2[i2]
      i2 += 1

      loop do
        break if op1.nil? && op2.nil?

        if self.class.delete?(op1)
          operation.delete(op1)
          op1 = ops1[i1]
          i1 += 1
          next
        end
        if self.class.insert?(op2)
          operation.insert(op2)
          op2 = ops2[i2]
          i2 += 1
          next
        end

        raise ArgumentError, "Cannot compose operations: first operation is too short." if op1.nil?
        raise ArgumentError, "Cannot compose operations: first operation is too long." if op2.nil?

        if self.class.retain?(op1) && self.class.retain?(op2)
          if op1 > op2
            operation.retain(op2)
            op1 -= op2
            op2 = ops2[i2]
            i2 += 1
          elsif op1 == op2
            operation.retain(op1)
            op1 = ops1[i1]
            i1 += 1
            op2 = ops2[i2]
            i2 += 1
          else
            operation.retain(op1)
            op2 -= op1
            op1 = ops1[i1]
            i1 += 1
          end
        elsif self.class.insert?(op1) && self.class.delete?(op2)
          if op1.length > -op2
            op1 = op1.slice(-op2, op1.length)
            op2 = ops2[i2]
            i2 += 1
          elsif op1.length == -op2
            op1 = ops1[i1]
            i1 += 1
            op2 = ops2[i2]
            i2 += 1
          else
            op2 += op1.length
            op1 = ops1[i1]
            i1 += 1
          end
        elsif self.class.insert?(op1) && self.class.retain?(op2)
          if op1.length > op2
            operation.insert(op1.slice(0, op2))
            op1 = op1.slice(op2, op1.length)
            op2 = ops2[i2]
            i2 += 1
          elsif op1.length == op2
            operation.insert(op1)
            op1 = ops1[i1]
            i1 += 1
            op2 = ops2[i2]
            i2 += 1
          else
            operation.insert(op1)
            op2 -= op1.length
            op1 = ops1[i1]
            i1 += 1
          end
        elsif self.class.retain?(op1) && self.class.delete?(op2)
          if op1 > -op2
            operation.delete(op2)
            op1 += op2
            op2 = ops2[i2]
            i2 += 1
          elsif op1 == -op2
            operation.delete(op2)
            op1 = ops1[i1]
            i1 += 1
            op2 = ops2[i2]
            i2 += 1
          else
            operation.delete(op1)
            op2 += op1
            op1 = ops1[i1]
            i1 += 1
          end
        else
          raise ArgumentError, "This shouldn't happen: op1: #{op1.inspect}, op2: #{op2.inspect}"
        end
      end

      operation
    end

    def should_be_composed_with?(other)
      return true if noop? || other.noop?

      start_a = start_index
      start_b = other.start_index
      simple_a = simple_op
      simple_b = other.simple_op
      return false unless simple_a && simple_b

      if self.class.insert?(simple_a) && self.class.insert?(simple_b)
        return start_a + simple_a.length == start_b
      end

      if self.class.delete?(simple_a) && self.class.delete?(simple_b)
        return (start_b - simple_b == start_a) || start_a == start_b
      end

      false
    end

    def should_be_composed_with_inverted?(other)
      return true if noop? || other.noop?

      start_a = start_index
      start_b = other.start_index
      simple_a = simple_op
      simple_b = other.simple_op
      return false unless simple_a && simple_b

      if self.class.insert?(simple_a) && self.class.insert?(simple_b)
        return start_a + simple_a.length == start_b || start_a == start_b
      end

      if self.class.delete?(simple_a) && self.class.delete?(simple_b)
        return start_b - simple_b == start_a
      end

      false
    end

    def self.transform(operation1, operation2)
      if operation1.base_length != operation2.base_length
        raise ArgumentError, "Both operations have to have the same base length"
      end

      operation1prime = new
      operation2prime = new
      ops1 = operation1.ops
      ops2 = operation2.ops
      i1 = 0
      i2 = 0
      op1 = ops1[i1]
      i1 += 1
      op2 = ops2[i2]
      i2 += 1

      loop do
        break if op1.nil? && op2.nil?

        if insert?(op1)
          operation1prime.insert(op1)
          operation2prime.retain(op1.length)
          op1 = ops1[i1]
          i1 += 1
          next
        end
        if insert?(op2)
          operation1prime.retain(op2.length)
          operation2prime.insert(op2)
          op2 = ops2[i2]
          i2 += 1
          next
        end

        raise ArgumentError, "Cannot compose operations: first operation is too short." if op1.nil?
        raise ArgumentError, "Cannot compose operations: first operation is too long." if op2.nil?

        if retain?(op1) && retain?(op2)
          if op1 > op2
            minl = op2
            op1 -= op2
            op2 = ops2[i2]
            i2 += 1
          elsif op1 == op2
            minl = op2
            op1 = ops1[i1]
            i1 += 1
            op2 = ops2[i2]
            i2 += 1
          else
            minl = op1
            op2 -= op1
            op1 = ops1[i1]
            i1 += 1
          end
          operation1prime.retain(minl)
          operation2prime.retain(minl)
        elsif delete?(op1) && delete?(op2)
          if -op1 > -op2
            op1 -= op2
            op2 = ops2[i2]
            i2 += 1
          elsif op1 == op2
            op1 = ops1[i1]
            i1 += 1
            op2 = ops2[i2]
            i2 += 1
          else
            op2 -= op1
            op1 = ops1[i1]
            i1 += 1
          end
        elsif delete?(op1) && retain?(op2)
          if -op1 > op2
            minl = op2
            op1 += op2
            op2 = ops2[i2]
            i2 += 1
          elsif -op1 == op2
            minl = op2
            op1 = ops1[i1]
            i1 += 1
            op2 = ops2[i2]
            i2 += 1
          else
            minl = -op1
            op2 += op1
            op1 = ops1[i1]
            i1 += 1
          end
          operation1prime.delete(minl)
        elsif retain?(op1) && delete?(op2)
          if op1 > -op2
            minl = -op2
            op1 += op2
            op2 = ops2[i2]
            i2 += 1
          elsif op1 == -op2
            minl = op1
            op1 = ops1[i1]
            i1 += 1
            op2 = ops2[i2]
            i2 += 1
          else
            minl = op1
            op2 += op1
            op1 = ops1[i1]
            i1 += 1
          end
          operation2prime.delete(minl)
        else
          raise ArgumentError, "The two operations aren't compatible"
        end
      end

      [ operation1prime, operation2prime ]
    end

    private

    def simple_op
      case @ops.length
      when 1
        @ops[0]
      when 2
        if self.class.retain?(@ops[0])
          @ops[1]
        elsif self.class.retain?(@ops[1])
          @ops[0]
        end
      when 3
        if self.class.retain?(@ops[0]) && self.class.retain?(@ops[2])
          @ops[1]
        end
      end
    end

    def start_index
      self.class.retain?(@ops[0]) ? @ops[0] : 0
    end
  end
end
