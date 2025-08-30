# IndexAccess

A PostgreSQL-focused Ruby gem that leverages advanced indexing features to automatically generate optimized ActiveRecord scopes. Supports GIN, GiST, partial, expression indexes and more.

## Overview

IndexAccess automatically generates ActiveRecord scopes based on your PostgreSQL indexes, making it easy to write queries that are guaranteed to use database indexes for optimal performance. It goes beyond basic B-tree indexes to support PostgreSQL's advanced features like JSONB operations, full-text search, and similarity matching.

For instance, if the table `todos` has a GIN index on a JSONB `metadata` column, developers can write `Todo.index_metadata_contains({status: 'urgent'})` to perform optimized JSONB containment queries.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'index_access'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install index_access
```

## Usage

### Basic B-tree Index Example

Given a `todos` table with a standard index:

```sql
CREATE INDEX index_todos_on_due_at ON todos (due_at);
```

IndexAccess will automatically generate a scope:

```ruby
# Instead of writing:
Todo.where(due_at: some_date)

# You can write:
Todo.index_due_at(some_date)
```

### Composite Index Example

For composite indexes:

```sql
CREATE INDEX index_todos_on_user_id_and_status ON todos (user_id, status);
```

You can use:

```ruby
Todo.index_user_id_and_status(user_id: 123, status: 'pending')
```

Note: you must pass in all arguments or you will get an ArgumentError

```ruby
Todo.index_user_id_and_status(user_id: 123)
# => ArgumentError => 'argument: 'status' is required'
```

### Partial Index Support

For partial indexes with conditions:

```sql
CREATE INDEX index_todos_on_due_at WHERE completed = false;
```

The generated scope will automatically include the partial index conditions:

```ruby
Todo.index_due_at(some_date)  # Automatically includes WHERE completed = false
```

### JSONB GIN Index Support

For JSONB columns with GIN indexes:

```sql
CREATE INDEX index_todos_on_metadata ON todos USING gin (metadata);
```

IndexAccess generates multiple optimized scopes:

```ruby
# Containment queries (@>)
Todo.index_metadata_contains({priority: 'high', category: 'work'})

# Contained by queries (<@)  
Todo.index_metadata_contained({priority: 'high', category: 'work', status: 'pending'})

# Key existence queries (?)
Todo.index_metadata_has_key('priority')

# Multiple key existence (?&)
Todo.index_metadata_has_keys(['priority', 'category'])

# Path-based queries (#>>)
Todo.index_metadata_path('user.preferences.theme', 'dark')
```

### Full-Text Search with GIN Indexes

For tsvector columns or expression indexes:

```sql
CREATE INDEX index_todos_fulltext ON todos USING gin (to_tsvector('english', title || ' ' || description));
```

Generated scope for full-text search:

```ruby
# Full-text search using @@
Todo.index_todos_fulltext_search('urgent deadline')
```

### Trigram Similarity with GIN Indexes

For fuzzy string matching:

```sql
CREATE INDEX index_todos_title_trgm ON todos USING gin (title gin_trgm_ops);
```

Generated scope:

```ruby
# Similarity search with configurable threshold
Todo.index_title_similar('importante', 0.3)  # Returns results ordered by similarity
```

### Expression Index Support

For expression indexes:

```sql
CREATE INDEX index_todos_lower_title ON todos (lower(title));
```

Generated scope:

```ruby
# Automatically uses the expression index
Todo.index_lower_title('my important task')
```

### Chaining Index Scopes

Index scopes can be chained together for complex queries:

```ruby
# Multiple single-column indexes
Todo.index_user_id(123).index_status('pending').index_priority('high')

# Chain with regular ActiveRecord methods
Todo.index_due_at(Date.today).limit(10).order(:created_at)

# Combine with custom scopes
Todo.index_user_id(user.id).recent.completed
```

### Advanced Composite Index Usage

For complex composite indexes, IndexAccess supports flexible argument patterns:

```ruby
# Given: CREATE INDEX idx_complex ON todos (user_id, status, due_at, priority)

# Full specification (most performant)
Todo.index_user_id_status_due_at_priority(
  user_id: 123, 
  status: 'pending', 
  due_at: Date.today, 
  priority: 'high'
)

# Partial specification (uses index prefix)
Todo.index_user_id_status_due_at_priority(user_id: 123, status: 'pending')

# Hash-based syntax for readability
Todo.index_user_id_status_due_at_priority({
  user_id: 123,
  status: 'pending'
})
```

## Configuration

Configure IndexAccess in an initializer:

```ruby
# config/initializers/index_access.rb
IndexAccess.configure do |config|
  # Customize scope naming convention
  config.scope_prefix = 'index_'
  
  # Enable/disable automatic scope generation
  config.auto_generate = true
  
  # Specify which models to include (default: all)
  config.included_models = ['Todo', 'User']
  
  # Or exclude specific models
  config.excluded_models = ['InternalLog', 'TempData']
end
```

## Requirements

- Ruby 3.0+
- Rails 7.0+  
- PostgreSQL 12+
- pg gem 1.1+

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests.

Use `bin/go` to run the full development workflow (setup, tests, and linting).

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ajsharma/index_access.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

