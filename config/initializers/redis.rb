require 'redis-namespace'
redis_connection = Redis.new(:host => "127.0.0.1", :port => "6379", :thread_safe => true)
Redis.current = Redis::Namespace.new(:eventr, :redis => redis_connection)

$eventr_redis = Redis::Namespace.new(:eventr_app, :redis => redis_connection)