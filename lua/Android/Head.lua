--[[头文件]]
Head = {}

Head.path =  "../lua/base/?.lua;./lua/base/?.lua;" ..
"../lua/base/socket/?.lua;./lua/base/socket/?.lua;" ..
"../lua/public/?.lua;./lua/public/?.lua;" ..
"../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" ..
"../lua/Android/?.lua;./lua/Android/?.lua;" ..
"../lua/Android/Config/?.lua;./lua/Android/Config/?.lua;" ..
"../lua/protocol/pb/?.lua;./lua/protocol/pb/?.lua;" ..
package.path

package.path = Head.path

return Head
