# WhereIndex

**Write index-aware Rails code with confidence.** WhereIndex automatically generates ActiveRecord scopes that make it clear which queries are designed to leverage your PostgreSQL indexes.

```ruby
# Before: Unclear relationship to your indexes
Todo.where(metadata: {priority: 'high'})  # Will this use your GIN index?
Todo.where('title ILIKE ?', '%urgent%')   # What about your trigram index?

# After: Index-aware code that documents intent
Todo.where_index_metadata_contains(priority: 'high')  # Clearly designed for GIN index
Todo.where_index_title_similar('urgent', 0.3)         # Obviously uses trigram matching
```

## Why Your Rails App Needs WhereIndex

- **Prevent Accidental Performance Issues** - Make index-optimized queries explicit and maintainable  
- **Unlock Advanced PostgreSQL** - Use JSONB, full-text search, and trigram matching with clean Ruby syntax  
- **Self-Documenting Code** - Show which queries are designed to leverage specific indexes  
- **Performance-Friendly Readability** - Write code that clearly indicates its optimization strategy

## The Hidden Problem Killing Your App's Performance

As Rails applications scale, teams optimize with PostgreSQL indexes. But here's what happens next:

```ruby
# You carefully craft an index
CREATE INDEX CONCURRENTLY idx_todos_user_pending ON todos (user_id) WHERE status = 'pending';

# Months later, someone "improves" the code
# OLD: Todo.where(user_id: user.id, status: 'pending')  ✅ Uses index
# NEW: Todo.where(user_id: user.id).where(status: status)  ❌ Might not!

# Result: Queries slow down, customers complain, incidents happen
```

**The real problem:** Rails makes it unclear when queries are designed to leverage indexes. Teams lose track of which optimizations exist and how to use them properly.

## The WhereIndex Solution

WhereIndex reads your PostgreSQL indexes and generates explicit, readable scopes that:
- **Make index-optimized queries obvious** in your application code
- **Document the relationship** between queries and database structure
- **Provide clean syntax** for advanced PostgreSQL features
- **Help maintain performance** by making optimization strategies visible

Instead of guessing whether your `.where()` chains will be fast, you write code that clearly shows its performance intent.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'where_index'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install where_index
```

## Quick Start

WhereIndex works by analyzing your existing PostgreSQL indexes and generating corresponding ActiveRecord scopes. Just add the gem and start using your indexes safely.

### 30-Second Example

```ruby
# 1. Add WhereIndex to your model
class Todo < ApplicationRecord
  include WhereIndex::ModelExtension
end

# 2. Your existing index becomes a readable scope
# CREATE INDEX index_todos_on_due_at ON todos (due_at);
Todo.where_index_due_at(Date.today)  # Clear intent to use due_at index

# 3. Composite indexes become type-safe methods  
# CREATE INDEX idx_user_status ON todos (user_id, status);
Todo.where_index_user_id_and_status(user_id: 123, status: 'pending')
```

## Advanced PostgreSQL Features Made Simple

### Composite Index Example

For composite indexes:

```sql
CREATE INDEX index_todos_on_user_id_and_status ON todos (user_id, status);
```

You can use:

```ruby
Todo.where_index_user_id_and_status(user_id: 123, status: 'pending')
```

Note: you must pass in all arguments or you will get an ArgumentError

```ruby
Todo.where_index_user_id_and_status(user_id: 123)
# => ArgumentError => 'argument: 'status' is required'
```

### Partial Index Support

For partial indexes with conditions:

```sql
CREATE INDEX index_todos_on_due_at WHERE completed = false;
```

The generated scope will automatically include the partial index conditions:

```ruby
Todo.where_index_due_at(some_date)  # Automatically includes WHERE completed = false
```

### 🚀 JSONB Operations (No SQL Required)

Stop writing raw SQL for JSONB queries. WhereIndex turns your GIN indexes into intuitive Ruby methods:

```sql
CREATE INDEX index_todos_on_metadata ON todos USING gin (metadata);
```

```ruby
# Complex JSONB queries become simple method calls
Todo.where_index_metadata_contains(priority: 'high', category: 'work')    # @> operator
Todo.where_index_metadata_contained({priority: 'high', status: 'done'})   # <@ operator  
Todo.where_index_metadata_has_key('priority')                             # ? operator
Todo.where_index_metadata_has_keys(['priority', 'category'])              # ?& operator
Todo.where_index_metadata_path('user.preferences.theme', 'dark')          # #>> operator

# All queries are structured to work well with your GIN index
```

### Full-Text Search with GIN Indexes

For tsvector columns or expression indexes:

```sql
CREATE INDEX index_todos_fulltext ON todos USING gin (to_tsvector('english', title || ' ' || description));
```

Generated scope for full-text search:

```ruby
# Full-text search using @@
Todo.where_index_todos_fulltext_search('urgent deadline')
```

### Trigram Similarity with GIN Indexes

For fuzzy string matching:

```sql
CREATE INDEX index_todos_title_trgm ON todos USING gin (title gin_trgm_ops);
```

Generated scope:

```ruby
# Similarity search with configurable threshold
Todo.where_index_title_similar('importante', 0.3)  # Returns results ordered by similarity
```

### Expression Index Support

For expression indexes:

```sql
CREATE INDEX index_todos_lower_title ON todos (lower(title));
```

Generated scope:

```ruby
# Automatically uses the expression index
Todo.where_index_lower_title('my important task')
```

### Chaining Index Scopes

Index scopes can be chained together for complex queries:

```ruby
# Multiple single-column indexes
Todo.where_index_user_id(123).index_status('pending').index_priority('high')

# Chain with regular ActiveRecord methods
Todo.where_index_due_at(Date.today).limit(10).order(:created_at)

# Combine with custom scopes
Todo.where_index_user_id(user.id).recent.completed
```

### Advanced Composite Index Usage

For complex composite indexes, WhereIndex supports flexible argument patterns:

```ruby
# Given: CREATE INDEX idx_complex ON todos (user_id, status, due_at, priority)

# Full specification (most performant)
Todo.where_index_user_id_status_due_at_priority(
  user_id: 123, 
  status: 'pending', 
  due_at: Date.today, 
  priority: 'high'
)

# Partial specification (uses index prefix)
Todo.where_index_user_id_status_due_at_priority(user_id: 123, status: 'pending')

# Hash-based syntax for readability
Todo.where_index_user_id_status_due_at_priority({
  user_id: 123,
  status: 'pending'
})
```

## Configuration

Configure WhereIndex in an initializer:

```ruby
# config/initializers/index_access.rb
WhereIndex.configure do |config|
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

