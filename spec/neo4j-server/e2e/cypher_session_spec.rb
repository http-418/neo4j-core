require 'spec_helper'

module Neo4j::Server


  describe CypherSession, api: :server do

    def open_session
      create_server_session
    end

    def open_named_session(name, default = nil)
      create_named_server_session(name, default)
    end

    it_behaves_like "Neo4j::Session"

    describe 'named sessions' do

      before { Neo4j::Session.current && Neo4j::Session.current.close}
      after { Neo4j::Session.current && Neo4j::Session.current.close}

      it 'stores a named session' do
        name = :test
        test = open_named_session(name)
        Neo4j::Session.named(name).should == test
      end

      it 'does not override the current session when default = false' do
        default = open_session
        Neo4j::Session.current.should == default
        name = :test
        open_named_session(name)
        Neo4j::Session.current.should == default
      end

      it 'makes the new session current when default = true' do
        default = open_session
        Neo4j::Session.current.should == default
        name = :test
        test = open_named_session(name, true)
        Neo4j::Session.current.should == test
      end
    end

    describe '_query' do
      let(:a_node_id) do
        result = session.query("CREATE (n) RETURN ID(n) AS id")
        result.first[:id];
      end

      it 'returns a result containing data,columns and error?' do
        result = session._query("START n=node(#{a_node_id}) RETURN ID(n)")
        result.data.should == [[a_node_id]]
        result.columns.should == ['ID(n)']
        result.error?.should be_false
      end

      it "allows you to specify parameters" do
        result = session._query("START n=node({myparam}) RETURN ID(n)", myparam: a_node_id)
        result.data.should == [[a_node_id]]
        result.columns.should == ['ID(n)']
        result.error?.should be_false
      end

      it 'returns error codes if not a valid cypher query' do
        result = session._query("SSTART n=node(0) RETURN ID(n)")
        result.error?.should be_true
        result.error_msg.should =~ /Invalid input/
        result.error_status.should == 'SyntaxException'
        result.error_code.should_not be_empty
      end
    end

    describe 'find_nodes' do
      before do
        session.query("CREATE (n:label { name : 'test', id: 2, version: 1.1 })")
      end

      after do
        session.query("MATCH (n:`label`) DELETE n")
      end

      def verify(node)
        node[:id].should == 2
        node[:name].should == "test"
        node[:version].should == 1.1
      end

      it 'allows finding nodes by a key with a Fixnum value' do
        node = session.find_nodes(:label, :id, 2).first
        verify node
      end

      it 'allows finding nodes by a key with a String value' do
        node = session.find_nodes(:label, :name, "test").first
        verify node
      end

      it 'allows finding nodes by a key with a Float value' do
        node = session.find_nodes(:label, :version, 1.1).first
        verify node
      end
    end
  end

end
