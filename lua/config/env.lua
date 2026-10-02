_G.EnvFlag = "prod"
local prod_config = {
    adminHost = "http://172.10.31.103:8888",
    assetsHost = "http://127.0.0.1:7841",
    eventHost = "http://127.0.0.1:6831", -- 活动服务相关
    jwtSecret = "a,yP338xMT=Vjvpc4y%LRv*H)%.)}Ea~"
}
local pre_config = {
    adminHost = "http://127.0.0.1:8888",
    assetsHost = "http://127.0.0.1:7841",
    eventHost = "http://127.0.0.1:6831", -- 活动服务相关
    jwtSecret = "57AKCyt4bc24@YBKat74eR#384fm:nWk",
    assetsPri =  [[
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDeiV0K919UOKOJ
5//sGeTJO9IB7mRw86d8eNq32m/9RSfwF+3iOuP68gpV0gkPGVxKB3oPnaJUyKJn
swdIwl7qlZzl1iYANgguSuDRfjELK/rztWxL5azCEIPagSuEnPDjqTH7wDjMeQ5U
jFyAXZIi3fveskHEZRswgWTSB6LOBwqNHQNGxAapvna4gPZcioBfiU6cnqWVzfr5
is9bHqTDHScpX/w1acGTFt2fNnW0bLuF65szWNgY3Sn2MfYxKKmdSoAVcDnONMHW
9L9yvZ/hVoB2ea4hVcZIGAHw1vX/5drwwsJILsN0JJoLy8iZQysR/fn8+jkfuara
VTFoJy8lAgMBAAECggEADZZMRJrwvbJGy4KLWqQEfWp8mqEujfYid/QWqC3bGco6
82rSm5x5RpCFCjmS7Tjg+XG8nyJCj6cMW2tP4STIKZrm6hWJwaHxT+12DcE4FCfx
E440Xx68mvPp/DfxkanVzC1zBgPCtAe0Ia9l1Ar8HP4ThPftq6SssbWrLTOwJtOk
Cs6ZVSU4OPliLufX7OuajyPF23EtcBfyjYouPcll25Eu00ev/lmM24DovPEl6Qzh
x4YgcSnEqbK+nZ/bwtVPvsH8Hm4+LRTFkWsRbHtMUJWCgHn5wjMMed/4rMKKuD/T
5Yzo+VDp7ih94Xwny+tLR9F2bkKFBCmDEPLouSWjpQKBgQDiKcPsMoy9gqC1IsSh
RuwdZSp5DUmZEGv5JhZMa+4GSkvYJ/23BErs9Ll7owTr3dOKSc5TA/hTIWmHhwrr
Kvmvse4uqXJpTu6XFSiFWgwqHutoAo1NyqnKcV0vtq22uJIPMS6y64BzggEOiJ0j
Vn/UNMOyAdkJxdufd+EVJ9mLhwKBgQD75R4YB4aeusn5Tb8RkJaThyAi6GmUop8d
ljHFb0vRyMLtS3Z098zS1isOKIzRfkjB/Xx+4VLdavTWHgYvYhbOkE/qDwJEUHVn
qhKS86e5C7wwI2Ik4R5vUsD0FqpPfbl1syqQ1pdNj7BOVqoNmn8C4UZRkd0yjrer
PDJPqPXS8wKBgQDObyjyc8GbSZy/OZkZTM9AlZMLI2HGYQLtTCKWZv3AqBhKmVYw
s65gU5DqlYZsdPIeC/hUNg94ccsNdeo1deiqwlKSLQDNtsp5BUsTTXpFCCv/qDSq
iQ4qRwe0AZ7WZeqMC2yAzA1XYZbtWS11kALmA7OMy7r7/KnXCWleEh20CQKBgQDs
EjI9+u+jWxNm3gIvh/5WjNEFZiNs9WuB4v0KN+Aq36gvlAWUYZhIEAeR4Vb4Dw5J
IDPJBYsPj+mdsc3CIn+VX5JFnYNWWsFtQereZhPOTL01sDOOtJw9YKUNHSDIFt/0
+tDtpO9v9TYadQYycZSPMmkgkT9o3nArvuK33XVlGQKBgHXIef6G6EWtPkj5JJl8
e+Dt/ys0oYuSk0CAniEvTBaO1uJrXdIXhwhKTmJfVvNr2a4ZB5/aOULMtxYZOvci
Jf7+yXsb9WiN2/nKjXBBr3/Xxbe3MHPSyfdp4zOSMo9Hhcqw721gBLznT+vMHF+u
iWixyuK4MkUtayUcFpAuhTVj
-----END PRIVATE KEY-----
    ]]
}
if _G.EnvFlag == "prod" then
    return prod_config
else
    return pre_config
end
