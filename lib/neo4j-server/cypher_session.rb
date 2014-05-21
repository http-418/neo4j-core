module Neo4j::Server

  # Plugin
  Neo4j::Session.register_db(:server_db) do |*url_opts|
    Neo4j::Server::CypherSession.open(*url_opts)
  end

  class CypherSession < Neo4j::Session
    include Resource
    include Neo4j::Core::CypherTranslator
    
    alias_method :super_query, :query


    # Opens a session to the database
    # @see Neo4j::Session#open
    #
    # @param url - defaults to 'http://localhost:7474' if not given
    # @params - see https://github.com/jnunemaker/httparty/blob/master/lib/httparty.rb for supported
    # HTTParty options
    def self.open(endpoint_url=nil, params = {})
      endpoint = Neo4jServerEndpoint.new(params)
      url = endpoint_url || 'http://localhost:7474'
      response = endpoint.get(url)
      raise "Server not available on #{url} (response code #{response.code})" unless response.code == 200
      
      root_data = JSON.parse(response.body)
      data_url = root_data['data']
      data_url << '/' unless data_url.end_with?('/')

      CypherSession.new(data_url, endpoint)
    end

    def initialize(data_url, endpoint = nil)
      @endpoint = endpoint || Neo4jServerEndpoint.new(data_url)
      Neo4j::Session.register(self)
      initialize_resource(data_url)
      Neo4j::Session._notify_listeners(:session_available, self)
    end

    def to_s
      "CypherSession #{@resource_url}"
    end

    def initialize_resource(data_url)
      response = @endpoint.get(data_url)
      expect_response_code(response,200)
      data_resource = JSON.parse(response.body)
      raise "No data_resource for #{response.body}" unless data_resource
      # store the resource data
      init_resource_data(data_resource, data_url)
    end

    def close
      super
      Neo4j::Transaction.unregister_current
    end

    def begin_tx
      Thread.current[:neo4j_curr_tx] = wrap_resource(self, 'transaction', CypherTransaction, nil, :post, @endpoint)
    end

    def create_node(props=nil, labels=[])
      l = labels.empty? ? "" : ":" + labels.map{|k| "`#{k}`"}.join(':')
      q = "CREATE (n#{l} #{cypher_prop_list(props)}) RETURN ID(n)"
      cypher_response = _query_or_fail(q, true)
      CypherNode.new(self, cypher_response)
    end

    def load_node(neo_id)
      cypher_response = _query("START n=node(#{neo_id}) RETURN n")
      if (!cypher_response.error?)
        CypherNode.new(self, neo_id)
      elsif (cypher_response.error_status == 'EntityNotFoundException')
        return nil
      else
        cypher_response.raise_error
      end
    end

    def load_relationship(neo_id)
      cypher_response = _query("START r=relationship(#{neo_id}) RETURN r")
      if (!cypher_response.error?)
        CypherRelationship.new(self, neo_id)
      elsif (cypher_response.error_msg =~ /not found/)  # Ugly that the Neo4j API gives us this error message
        return nil
      else
        cypher_response.raise_error
      end
    end

    def create_label(name)
      CypherLabel.new(self, name)
    end

    def indexes(label)
      response = @endpoint.get("#{@resource_url}schema/index/#{label}")
      expect_response_code(response, 200)
      data_resource = JSON.parse(response.body)

      property_keys = data_resource.map do |row|
        row['property_keys'].map(&:to_sym)
      end

      {
          property_keys: property_keys
      }
    end

    def find_all_nodes(label_name)
      response = _query_or_fail("MATCH (n:`#{label_name}`) RETURN ID(n)")
      search_result_to_enumerable(response)
    end

    def find_nodes(label_name, key, value)
      value = "'#{value}'" if value.is_a? String
      
      response = _query_or_fail <<-CYPHER
        MATCH (n:`#{label_name}`)
        WHERE n.#{key} = #{value}
        RETURN ID(n)
      CYPHER
      search_result_to_enumerable(response)
    end

    def query(*params, &query_dsl)
      result = super
      if result.error?
        raise Neo4j::Session::CypherError.new(result.error_msg, result.error_code, result.error_status)
      end
      result.to_hash_enumeration
    end

    # TODO remove this function and do not use cypher DSL internally
    def _query_internal(*params, &query_dsl)
      super_query(*params, &query_dsl)
    end

    def _query_or_fail(q, single_row = false, params=nil)
      response = _query(q, params)
      response.raise_error if response.error?
      single_row ? response.first_data : response
    end

    def query_default_return
      " RETURN ID(n)"
    end

    def _query(q, params=nil)
      curr_tx = Neo4j::Transaction.current
      if (curr_tx)
        curr_tx._query(q, params)
      else
        url = resource_url('cypher')
        q = params.nil? ? {query: q} : {query: q, params: params}
        response = @endpoint.post(url, headers: resource_headers, body: q.to_json)
        CypherResponse.create_with_no_tx(response)
      end
    end

    def search_result_to_enumerable(response)
      return [] unless response.data

      def descent(outer_data)
        Enumerator.new do |yielder|
          outer_data.each do |inner_data|
            yielder << ( inner_data[0].kind_of?(Array) ?
                         descent( inner_data[0].map{ |n| [n] } ) :
                         CypherNode.new(self, inner_data[0]).wrapper  )
          end
        end
      end
      descent(response.data)
    end

  end
end
