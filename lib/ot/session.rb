require "monitor"

module OT
  class Session
    attr_reader :server, :users

    def initialize(document = "", operations = [], base_revision = 0)
      @server = Server.new(document, operations, base_revision)
      @users = {}
      @lock = Monitor.new
    end

    def synchronize(&block)
      @lock.synchronize(&block)
    end

    def document
      @server.document
    end

    def revision
      @server.revision
    end

    def get_client(client_id)
      @users[client_id] ||= {}
    end

    def remove_client(client_id)
      @users.delete(client_id)
    end

    def clients_payload
      @users.each_with_object({}) do |(client_id, payload), result|
        result[client_id] = {}
        result[client_id][:name] = payload[:name] if payload[:name]
        result[client_id][:selection] = payload[:selection].as_json if payload[:selection]
      end
    end
  end
end
