--
--  sm2 test
--  作用: 给洗牌后的牌使用sm2算法加解密
--  使用步骤:
--  1. 获取公钥和私钥: sm2.initkey()
--     每个用户生成一个公钥和密钥，其中密钥密钥需要发送给每一个用户
--     密钥需要使用加密方法传输给对方

--  2. 调用sm2.encrypt()加密
--  
--  3. 调用sm2.decrypt()解密
--
-- 注意: sm2设计有个缺陷，sm2对象在加解密过程中key设计为全局变量，所以如果要多个对象进行加解密，
--      需要将sm2对象保存起来，不能使用全局变量保存sm2对象，如下示例 ：

local sm2 = require "sm2"

local client1 = {}
local client2 = {}
local client3 = {}

-- sm2包装到table里面，防止sm2内部全局的key影响
client1.sm2 = sm2
client2.sm2 = sm2
client3.sm2 = sm2

-- client1
local privateKey, publicKey  = client1.sm2.initkey()
print("pub len:" ..string.len(publicKey))
print(publicKey)
print('-----')
print("pri len" ..string.len(privateKey))
print(privateKey)
print('-----')

local cipher = client1.sm2.encrypt("hello world1")
print(string.len(cipher))
print(cipher)
print('-----')

local plain = client1.sm2.decrypt(cipher)
print(plain)
print('-----')

-- client2
local privateKey, publicKey  = client2.sm2.initkey()
print("pub len:" ..string.len(publicKey))
print(publicKey)
print('-----')
print("pri len" ..string.len(privateKey))
print(privateKey)
print('-----')

local cipher = client2.sm2.encrypt("hello world2")
print(string.len(cipher))
print(cipher)
print('-----')

local plain = client2.sm2.decrypt(cipher)
print(plain)
print('-----')

-- client3
local privateKey, publicKey  = client3.sm2.initkey()
print("pub len:" ..string.len(publicKey))
print(publicKey)
print('-----')
print("pri len" ..string.len(privateKey))
print(privateKey)
print('-----')

local cipher = client3.sm2.encrypt("hello world1")
print(string.len(cipher))
print(cipher)
print('-----')

local plain = client3.sm2.decrypt(cipher)
print(plain)
print('-----')