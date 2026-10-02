
Head ={}

Head.path = 
"../lua/base/?.lua;./lua/base/?.lua;" ..
"../lua/base/socket/?.lua;./lua/base/socket/?.lua;" ..
"../lua/public/?.lua;./lua/public/?.lua;" .. 
"./lua/public/DBSink/?.lua;" ..
"../lua/Gateway/?.lua;./lua/Gateway/?.lua;" .. 
"../lua/protocol/pb/?.lua;./lua/protocol/pb/?.lua;" ..
"../lua/base/logging/?.lua;./lua/base/logging/?.lua;" .. 
"../lua/DB_s/?.luia;./lua/DB_s/?.lua;" .. 
"../lua/Logon_s/?.lua;./lua/Logon_s/?.lua;"..
"./lua/HotFix/?.lua;" ..
package.path


return Head
