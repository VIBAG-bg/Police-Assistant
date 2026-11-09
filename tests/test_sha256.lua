local hash=require 'pa26_sha256'
eq(hash.digest(''),'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
eq(hash.digest('abc'),'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
eq(hash.digest('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),'248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1')
local yields=0;eq(hash.digest(string.rep('a',1000000),function()yields=yields+1 end),'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');check(yields>1000)
check(not pcall(hash.digest,string.rep('x',2097153)))
