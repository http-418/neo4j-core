# Neo4j-core v3.0 [![Code Climate](https://codeclimate.com/github/andreasronge/neo4j-core.png)](https://codeclimate.com/github/andreasronge/neo4j-core) [![Build Status](https://travis-ci.org/andreasronge/neo4j-core.png)](https://travis-ci.org/andreasronge/neo4j-core)

A simple Ruby wrapper around the Neo4j graph database that works with the server and embedded Neo4j API.
This gem can be used both from JRuby and normal MRI. You may get better performance using it from JRuby and the embedded
Neo4j, but it will probably be easier to develop (e.g. faster to run tests) on MRI and neo4j server.
This gem is designed to work well together with the neo4j active model compliant gem (see the 3.0 branch).

For the stable v2.0 version, see the v2.0 branch https://github.com/andreasronge/neo4j-core/tree/v2.x
Do not use this gem in production.


## Installation

You can use this gem in two different ways:

* embedded - talking directly to the database using the Neo4j Java API (only JRuby)
* server   - talking to the Neo4j Server via HTTP (Both JRuby and MRI)

### Embedded or Server Neo4j ?

I suggest you start using the Neo4j server instead of Neo4j embedded because it is easier to use for development.
If you later get performance problem (e.g. too many HTTP requests hitting the Neo4j Server)
you can try the embedded neo4j with almost no changes in your code base.
The embedded neo4j via JRuby also gives you direct access to the Neo4j Java API (e.g. the Neo4j Traversal API)
which can be used to do more powerful and efficient traversals.

### Usage from Neo4j Server

You need to install the Neo4j server. This can be done by using a Rake task.


Install the gem:
```
gem install neo4j-core --pre
```

Create a Rakefile with the following content:

```
require 'neo4j/tasks/neo4j_server'
```

Install and start neo4j by typing:
```
rake neo4j:install[community-2.0.2]
rake neo4j:start
```


### Usage from Neo4j Embedded

The Gemfile contains references to Neo4j Java libraries. Nothing is needed to be installed.
The embedded database is only accessible from JRuby (unlike the Neo4j Server).
No need to start the server since it is embedded.

## Neo4j-core API, v3.0

### API Documentation

* [Neo4j::Node](http://www.rubydoc.info/github/andreasronge/neo4j-core/Neo4j/Node)
* [Neo4j::Relationship](http://www.rubydoc.info/github/andreasronge/neo4j-core/Neo4j/Relationship)
* [Neo4j::Session](http://www.rubydoc.info/github/andreasronge/neo4j-core/Neo4j/Session)
* [Neo4j::Label](http://www.rubydoc.info/github/andreasronge/neo4j-core/Neo4j/Label)

See also [Neo4j Docs](http://docs.neo4j.org/)


### Database Session

There are currently two available types of session, one for connecting to a neo4j server
and one for connecting to the embedded Neo4j database (which requires JRuby).

Using the Neo4j Server: `:server_db`
Open a IRB/Pry session:

```ruby
  require 'neo4j-core'
  # Using Neo4j Server Cypher Database
  session = Neo4j::Session.open(:server_db)
```

### Session Configuration

Example, Basic Authentication:

```ruby
  Neo4j::Session.open(:server_db, 'http://my.server', basic_auth: { username: 'username', password: 'password'})
```

The last option hash is passed on to HTTParty. See here for more available options:
http://rdoc.info/github/jnunemaker/httparty/HTTParty/ClassMethods

### Embedded Session

Using the Neo4j Embedded Database, `:embedded_db`

```ruby
  # Using Neo4j Embedded Database
  session = Neo4j::Session.open(:embedded_db, '/folder/db', auto_commit: true)
  session.start
```

To stop the database (only supported via the embedded database) use
```
session.shutdown
session.running? #=> false
session.close # make the session not current/default
```

### Session.current

When a session has been created it will be stored in the `Neo4j::Session` object.
Example, get the default session

```ruby
session = Neo4j::Session.current
```

### Multiple Sessions

The default session is used by all operation unless specified as the last argument.
For example create a node with a different session:

```ruby
my_session = Neo4j::Session.create_session(:server_db, "http://localhost:7474")
Neo4j::Node.create(name: 'kalle', my_session)
```

When using the Neo4j Server: `:server_db`, multiple sessions are supported. They
can be created using the open_named method. This method takes two extra parameters,
the second parameter is the session name, and the third parameter is whether the new session should over-ride
the default session (becoming the session returned by calling `Neo4j::Session.current`).
Valid options are true (always become current), false (never become current) and nil (become current if no
existing current session).

```ruby
Neo4j::Session.open_named(:server_db, :test, true, "https://localhost:7474")
session = Neo4j::Session.named :test # Returns the session named :test.
session = Neo4j::Session.current # Returns the session named :test, because the 'default' flag was set to true.
```


### Label and Index Support

Create a node with an label `person` and one property
```ruby
Neo4j::Node.create({name: 'kalle'}, :person)
```

Add index on a label

```ruby
  person = Label.create(:person)
  person.create_index(:name) # compound keys will be supported in Neo4j 2.1

  # drop index
  person.drop_index(:name)
```

```ruby
  # which indexes do we have and on which properties,
  red.indexes.each {|i| puts "Index #{i.label} properties: #{i.properties}"}

  # drop index, we assume it's the first one we want
  red.indexes.first.drop(:name)

  # which indices exist ?
  # (compound keys will be supported in Neo4j 2.1 (?))
  red.indexes # => {:property_keys => [[:age]]}
```

Constraints

Only unique constraint and single property is supported (yet).

```ruby
label = Neo4j::Label.create(:person)
label.create_constraint(:name, type: :unique)
label.drop_constraint(:name, type: :unique)
```

### Creating Nodes

```ruby
  # notice, label argument can be both Label objects or string/symbols.
  node = Node.create({name: 'andreas'}, red, :green)
  puts "Created node #{node[:name]} with labels #{node.labels.map(&:name).join(', ')}"
```

Notice, nodes will be indexed based on which labels they have.

Setting properties

```ruby
  node = Node.create({name: 'andreas'}, red, :green)
  node[:name] = 'changed name' # changes immediately one property
  node[:name] # => 'changed name'
  node.props # => {name: 'changed name'}
  node.props={ foo: 42}  # replace all properties
  node.update_props( bar: 42) # keeps old properties (unlike #props=) update with given hash
```

Notice properties are never stored in ruby objects, instead they are always fetched from the database.

### Finding Nodes

Each node and relationship has a id, `neo_id`

```ruby
  node = Neo4j::Node.create
  # load the node again from the database
  node2 = Neo4j::Node.load(node.neo_id)
```

Finding nodes by label:

```ruby
  # Find nodes using an index, returns an Enumerable
  Neo4j::Label.find_nodes(:red, :name, "andreas")

  # Find all nodes for this label, returns an Enumerable
  Neo4j::Label.find_all_nodes(:red)

  # which labels does a node have ?
  node.labels # [:red]
```

Example, Finding with order by on label :person

```ruby
  Neo4j::Label.query(:person, order: [:name, {age: :asc}])
```


Conditions:

 ```ruby
   # exact search
   Neo4j::Label.query(:person, conditions: {name: 'andreas'}

   # regular expression
   Neo4j::Label.query(:person, conditions: {name: /AND.*/i})
 ```

### Transactions

By default each Neo4j operation is wrapped in an transaction.
If you want to execute several operation in one operation you can use the `Neo4j::Transaction` class, example:

```ruby
Neo4j::Transaction.run do
  n = Neo4j::Node.create(name: 'kalle')
  n[:age] = 42
end
```

Rollback occurs if an exception is thrown, or the failure method is called on the transaction.

E.g.

```ruby
Neo4j::Transaction.run do |tx|
  n = Neo4j::Node.create(name: 'kalle')
  tx.failure # all operations inside this tx will be rollbacked
  n[:age] = 42
end

```

### Relationship

How to create a relationship between node n1 and node n2 with one property

```ruby
n1 = Neo4j::Node.create
n2 = Neo4j::Node.create
rel = n1.create_rel(:knows, n2, since: 1994)

# Alternative
Neo4j::Relationship.create(:knows, n1, n2, since: 1994)
```

Setting properties on relationships works like setting properties on nodes.

Finding relationships

```ruby
# any type any direction any label
n1.rels

# Outgoing of one type:
n1.rels(dir: :outgoing, type: :know).to_a

# same but expects only one relationship
n1.rel(dir: :outgoing, type: :best_friend)

# several types
n1.rels(types: [:knows, :friend])

# label
n1.rels(label: :rich)

# matching several labels
n1.rels(labels: [:rich, :poor])

# outgoing between two nodes
n1.rels(dir: :outgoing, between: n2)
```

Returns nodes instead of relationships

```ruby
# same parameters as rels method
n1.nodes(dir: outgoing)
n1.node(dir: outgoing)
```


Delete relationship

```ruby
rel = n1.rel(:outgoing, :know) # expects only one relationship
rel.del
```


### Cypher

Example

```ruby
session = Neo4j::Session.current

session.query("CREATE (n {mydata: 'Hello'}) RETURN ID(n) AS id")

# Parameters
session.query("START n=node({a_parameter}) RETURN ID(n)", a_parameter: 0)

# DSL
session.query(a_parameter: 0) { node("{a_parameter}").neo_id.as(:foo) }
```

The `query` method returns an Enumeration of Hash values.

Example of loading Neo4j::Nodes from a cypher query

```ruby
result = session.query("START n=node(*) RETURN ID(n)")
nodes = result.map do |key_values|
  # just one column is returned in this example - :'ID(n)'
  node_id = key_values.values[0]
  Neo4j::Node.load(node_id)
end
```

Example, using the name of the column

```ruby
result = session.query("START n=node(0) RETURN ID(n) as mykey")
Neo4j::Node.load(result.first[:mykey])
```


## Implementation:

All method prefixed with `_` gives direct access to the java layer/rest layer.
Notice, the database starts with auto commit by default.

No state is cached in the neo4j-core (e.g. neo4j properties).

The public `Neo4j::Node` classes is abstract and provides a common API/docs for both the embedded and
  neo4j server.

The Neo4j::Embedded and Neo4j::Server modules contains drivers for classes like the `Neo4j::Node`.
This is implemented something like this:

```ruby
  class Neo4j::Node
    # YARD docs
    def [](key)
      # abstract method - impl using either HTTP or Java API
      get_property(key,session=Neo4j::Session.current)
    end


    def self.create(props, session=Neo4j::Session.current)
     session.create_node(props)
    end
  end
```

Both implementation use the same E2E specs.


## Testing

The testing will be using much more mocking.

* The `unit` rspec folder only contains testing for one Ruby module. All other modules should be mocked.
* The `integration` rspec folder contains testing for two or more modules but mocks the neo4j database access.
* The `e2e` rspec folder for use the real database (or Neo4j's ImpermanentDatabase)
* The `shared_examples` common specs for different types of databases


## The public API

* {Neo4j::Node} The Neo4j Node

* {Neo4j::Relationship} The Relationship

* {Neo4j::Session} The session to the embedded or server database.

* `Neo4j::Cypher` Cypher Query DSL, see {Neo4j Wiki}[https://github.com/andreasronge/neo4j/wiki/Neo4j%3A%3ACore-Cypher]


See also the cypher DSL gem, [Neo4j Wiki](https://github.com/andreasronge/neo4j/wiki/Neo4j%3A%3ACore-Cypher)

## Version 3.0

The neo4j-core version 3.0 uses the java Jar and/or the Neo4j Server version 2.0.0-M6+ . This mean that it should work on
Ruby implementation and not just JRuby !

It uses the new label feature in order to do mappings between `Neo4j::Node` (java objects) and your own ruby classes.

The code base for the 3.0 should be smaller and simpler to maintain because there is less work to be done in the
Ruby layer but also by removing features that are too complex or not that useful.

The neo4j-wrapper source code is included in this git repo until the refactoring has stabilized.
The old source code for neo4j-core is also included (lib.old). The old source code might later on be copied into the
 3.0 source code (the lib folder).

The neo4j-core gem will work for both the embedded Neo4j API and the server api.
That means that neo4j.rb will work on any Ruby implementation and not just JRuby. This is under investigation !
It's possible that some features for the Neo4j.rb 2.0 will not be available in the 3.0 version since it has to work
 with both the Neo4j server and Neo4j embedded APIs.

Since neo4j-core provides one unified API to both the server end embedded neo4j database the neo4j-wrapper and neo4j
gems will also work with server and embedded neo4j databases.

New features:

* neo4j-core provides the same API to both the Embedded database and the Neo4j Server
* auto commit is each operation is now default (neo4j-core)

Removed features:

* auto start of the database (neo4j-core)
* wrapping of Neo4j::Relationship java objects but there will be a work around (neo4j-wrapper)
* traversals (the outgoing/incoming/both methods) moves to a new gem, neo4j-traversal.
* rules will not be supported
* versioning will not be supported, will Neo4j support it ?
* multitenancy will not be supported, will Neo4j support it ?

Changes:

* `Neo4j::Node.create` now creates a node instead of `Neo4j::Node.new`
* `Neo4j::Node#rels` different arguments, see below
* Many Neo4j Java methods requires you to close an ResourceIterable as well as be in an transaction (even for read operations)
In neo4j-core there are two version of these methods, one that create transaction and close the iterable for you and one raw
where you have to do it yourself (which may give you be better performance).
* The neo4j-core includes the neo4j-wrapper implementation.

Future (when Neo4j 2.1 is released)
* Support for fulltext search
* Compound keys in index


## License
* Neo4j.rb - MIT, see the LICENSE file http://github.com/andreasronge/neo4j-core/tree/master/LICENSE.
* Lucene -  Apache, see http://lucene.apache.org/java/docs/features.html
* \Neo4j - Dual free software/commercial license, see http://neo4j.org/

Notice there are different license for the neo4j-community, neo4j-advanced and neo4j-enterprise jar gems.
Only the neo4j-community gem is by default required.
