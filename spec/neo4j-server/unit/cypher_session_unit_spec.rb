require 'spec_helper'

module Neo4j::Server
  describe CypherSession do
    
    before(:each) do
      @endpoint = Neo4jServerEndpoint.new()
    end

    let(:cypher_response) do
      double('cypher response', error?: false, first_data: [28])
    end

    let(:session) do
      CypherSession.any_instance.stub(:initialize_resource).and_return(nil)
      CypherSession.new('http://foo.bar')
    end

    class TestResponse
      attr_reader :body
      def initialize(body)
        @body = body.to_json
      end

      def code
        200
      end

      def request
        return Struct.new(:path).new('bla')
      end
    end

    describe 'create_session' do
      let(:root_resource_with_slash) do
        {
            "management"=>"http://localhost:7474/db/manage/",
            "data"=>"http://localhost:7474/db/data/"
        }
      end

      let(:root_resource_with_no_slash) do
        {
            "management"=>"http://localhost:7474/db/manage",
            "data"=>"http://localhost:7474/db/data"
        }
      end

      let(:data_resource) do
        {}
      end

      it 'allow root resource with urls ending with slash' do
        Neo4jServerEndpoint.should_receive(:new).with({}).and_return(@endpoint)
        
        @endpoint.should_receive(:get).with('http://localhost:7474').and_return(TestResponse.new(root_resource_with_slash))
        @endpoint.should_receive(:get).with("http://localhost:7474/db/data/").and_return(TestResponse.new(data_resource))
        
        session = Neo4j::Session.create_session(:server_db)
        expect(session.resource_url).to eq('http://localhost:7474/db/data/')
      end

      it 'allow root resource with urls NOT ending with slash' do
        Neo4jServerEndpoint.should_receive(:new).with({}).and_return(@endpoint)
        
        @endpoint.should_receive(:get).with('http://localhost:7474').and_return(TestResponse.new(root_resource_with_no_slash))
        @endpoint.should_receive(:get).with("http://localhost:7474/db/data/").and_return(TestResponse.new(data_resource))

        session = Neo4j::Session.create_session(:server_db)
        expect(session.resource_url).to eq('http://localhost:7474/db/data/')
      end

      it 'creates session with basic auth params' do
        base_url = 'http://localhost:7474'
        auth = {basic_auth: { username: 'username', password: 'password'}}
        params = [base_url, auth]

        Neo4jServerEndpoint.should_receive(:new).with(auth).and_return(@endpoint)
        
        @endpoint.should_receive(:get).with(base_url)
          .and_return(TestResponse.new(root_resource_with_slash))
        @endpoint.should_receive(:get).with("http://localhost:7474/db/data/")
          .and_return(TestResponse.new(data_resource))
          
        session = Neo4j::Session.create_session(:server_db, params)
      end

      it 'does work with two sessions' do
        base_url = 'http://localhost:7474'
        auth = {basic_auth: { username: 'username', password: 'password'}}
        params = [base_url, auth]

        Neo4jServerEndpoint.should_receive(:new).with(auth).and_return(@endpoint)
        @endpoint.should_receive(:get).with(base_url)
          .and_return(TestResponse.new(root_resource_with_slash))
        @endpoint.should_receive(:get).with("http://localhost:7474/db/data/")
          .and_return(TestResponse.new(data_resource))

        Neo4j::Session.create_session(:server_db, params)

        Neo4jServerEndpoint.should_receive(:new).with({}).and_return(@endpoint)
        @endpoint.should_receive(:get).with('http://localhost:7474')
          .and_return(TestResponse.new(root_resource_with_no_slash))
        @endpoint.should_receive(:get).with("http://localhost:7474/db/data/")
          .and_return(TestResponse.new(data_resource))
        
        Neo4j::Session.create_session(:server_db)
      end

    end

    describe 'instance methods' do

      describe 'load_node' do
        it "generates 'START v0 = node(1915); RETURN v0'" do
          session.should_receive(:_query).with("START n=node(1915) RETURN n").and_return(cypher_response)
          node = session.load_node(1915)
          node.neo_id.should == 1915
        end

        it "returns nil if EntityNotFoundException" do
          r = double('cypher response', error?: true, error_status: 'EntityNotFoundException')
          session.should_receive(:_query).with("START n=node(1915) RETURN n").and_return(r)
          session.load_node(1915).should be_nil
        end

        it "raise an exception if there is an error but not an EntityNotFoundException exception" do
          r = double('cypher response', error?: true, error_status: 'SomeError', response: double("response").as_null_object)
          r.should_receive(:raise_error)
          session.should_receive(:_query).with("START n=node(1915) RETURN n").and_return(r)
          session.load_node(1915)
        end
      end

      describe 'begin_tx' do
        let(:dummy_request) { double("dummy request", path: 'http://dummy.request')}

        after { Thread.current[:neo4j_curr_tx] = nil }

        let(:body) do
          <<-HERE
{"commit":"http://localhost:7474/db/data/transaction/1/commit","results":[],"transaction":{"expires":"Tue, 06 Aug 2013 21:35:20 +0000"},"errors":[]}
          HERE
        end

        it "create a new transaction and stores it in thread local" do
          response = double('response', headers: {'location' => 'http://tx/42'}, code: 201, request: dummy_request)
          response.should_receive(:[]).with('exception').and_return(nil)
          response.should_receive(:[]).with('commit').and_return('http://tx/42/commit')
          session.should_receive(:resource_url).with('transaction', nil).and_return('http://new.tx')
          
          session.instance_variable_set("@endpoint", @endpoint)
          @endpoint.should_receive(:post).with('http://new.tx', anything).and_return(response)
          
          tx = session.begin_tx
          tx.commit_url.should == 'http://tx/42/commit'
          tx.exec_url.should == 'http://tx/42'
          Thread.current[:neo4j_curr_tx].should == tx
        end
      end

      describe 'create_node' do

        before do
          session.stub(:resource_url).and_return("http://resource_url")
        end

        it "create_node() generates 'CREATE (v1) RETURN v1'" do
          session.stub(:resource_url).and_return
          session.should_receive(:_query).with("CREATE (n ) RETURN ID(n)", nil).and_return(cypher_response)
          session.create_node
        end

        it 'create_node(name: "jimmy") generates ' do
          session.should_receive(:_query).with("CREATE (n {name : 'jimmy'}) RETURN ID(n)",nil).and_return(cypher_response)
          session.create_node(name: 'jimmy')
        end

        it 'create_node({}, [:person])' do
          session.should_receive(:_query).with("CREATE (n:`person` {}) RETURN ID(n)",nil).and_return(cypher_response)
          session.create_node({}, [:person])
        end

        it "initialize a CypherNode instance" do
          session.should_receive(:_query).with("CREATE (n ) RETURN ID(n)",nil).and_return(cypher_response)
          n = double("cypher node")
          CypherNode.should_receive(:new).and_return(n)
          session.create_node
        end
      end

      describe 'find_nodes' do
        
        before do
          session.stub(:resource_url).and_return
          session.should_receive(:search_result_to_enumerable).with(cypher_response).and_return
        end

        it "should produce Cypher query with String values" do
          cypher_query = "        MATCH (n:`label`)\n        WHERE n.key = 'value'\n        RETURN ID(n)\n"
          session.should_receive(:_query_or_fail).with(cypher_query).and_return(cypher_response)
          session.find_nodes(:label,:key,"value")
        end

        it "should produce Cypher query with Fixnum values" do
          cypher_query = "        MATCH (n:`label`)\n        WHERE n.key = 4\n        RETURN ID(n)\n"
          session.should_receive(:_query_or_fail).with(cypher_query).and_return(cypher_response)
          session.find_nodes(:label,:key,4)
        end

        it "should produce Cypher query with Float values" do
          cypher_query = "        MATCH (n:`label`)\n        WHERE n.key = 4.5\n        RETURN ID(n)\n"
          session.should_receive(:_query_or_fail).with(cypher_query).and_return(cypher_response)
          session.find_nodes(:label,:key,4.5)
        end
      end

    end
  end
  
end
