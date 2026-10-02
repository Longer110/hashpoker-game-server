package.path = "../lua/base/protobuf/?.lua;./lua/base/protobuf/?.lua;" .. package.path

-- 协议部分
require 'test_pb'  
require 'Logon_pb'  
require 'Lobby_pb'   
require 'Chat_pb' 
require 'Gateway_pb' 
require 'NiuNiuGame_pb'
require 'NiuNiuGame2_pb' 
require 'BaijialeGame_pb'    
require 'qzBaijialeGame_pb'    
require 'tbBaijialeGame_pb' 
require 'ZhaJinHuaGame_pb'   
require 'SanGongGame_pb' 
require 'Android_pb'  
require 'Dian21_pb'  
require 'Dian21_2_pb'
require 'PubProto_pb' 
require 'PubProto1_pb' 
require 'DbServer_pb'
require 'DbServer1_pb'
require 'ErrorCode_pb'
require 'NotifyToCli_pb'
require 'Maintainer_pb' 

require 'MaJiang_pb'
require 'Log_pb'
require 'MaJiang1_pb'
require 'MaJiang2_pb'
require 'MaJiang3_pb'
require 'MaJiang4_pb'
require 'MaJiang5_pb'
require 'Backstage_pb'  
require 'Web_pb'    

require "MagicFace_pb"
require "PaiJiu_pb"
require "Buried_pb"
require "ErBaGang_pb"
require "BaiRenZhaJinHua_pb"
require 'YuXiaXieCenter_pb' 
require 'YuXiaXie_pb' 
require 'YuXiaXie2_pb'
require 'BaiJiaLeCenter_pb'
require 'BaiJiaLeSlave_pb'
require 'Texas_pb' 
require 'YuXiaXieJHCenter_pb'
require 'GaoBo_pb'
require 'SeDie_pb'

require 'PilotSlave_pb'
require 'PilotCenter_pb'
require 'CrossUnite_pb'
require 'JCCrossUnite_pb'
require 'PilotJCGame_pb'

require 'TouBaoCenter_pb'
require 'TouBao_pb' 
require 'LiveCGame_pb' 
require 'LiveSlave_pb' 

require 'SeDieMCenter_pb'
require 'SeDieMSlave_pb'

require 'FootBallSlave_pb'
require 'FootBallCenter_pb'

--require 'FellTreeCenter_pb' 
require 'FellTreeSlave_pb'

require 'ClubCenter_pb'
require 'ClubSlave_pb'
require 'ClubSlave2_pb'
require 'DbServerClub_pb'
require 'DbServerClub1_pb'

--require 'BasketballCenter_pb' 
require 'BasketballSlave_pb'
require 'DeZhouClubSC_pb'
require 'ClubQZNiuNiuGame_pb'

require 'NiuNiuCenter_pb'
require 'NiuNiuSlave_pb'
require 'OldHand_pb'
require 'TanQiu_pb'
require 'DbMiniGame_pb'
require 'DiShu_pb'
require 'TanXian_pb'
require('AutoBet_pb')
require('PilotSmallGame_pb')


ProtoManager = {} 
ProtoManager.test_pb = test_pb

-- 外部协议  
ProtoManager.Logon_pb = Logon_pb


ProtoManager.Lobby_pb = Lobby_pb 
ProtoManager.Lobby_Proto = ProtoManager.Lobby_pb.Lobby_Proto()

ProtoManager.Gateway_pb  = Gateway_pb 
ProtoManager.ErrorCode_pb=ErrorCode_pb

ProtoManager.Dian21_pb = Dian21_pb   
ProtoManager.Dian21_2_pb = Dian21_2_pb
ProtoManager.DianProto  = ProtoManager.Dian21_pb.Dian21Game_Proto()

ProtoManager.ZhaJinHuaGame_pb  = ZhaJinHuaGame_pb  
ProtoManager.ZhaJinHuaGamePro = ZhaJinHuaGame_pb.ZhaJinHuaGame_Proto()
ProtoManager.Android_pb = Android_pb
ProtoManager.NotifyToCli_pb =NotifyToCli_pb
ProtoManager.Maintainer_pb =Maintainer_pb
ProtoManager.Backstage_pb =Backstage_pb
ProtoManager.PaiJiu_pb =PaiJiu_pb
ProtoManager.PaiJiuPro = PaiJiu_pb.PaiJiu_Proto()
-- 麻将
ProtoManager.MaJiang_pb =MaJiang_pb
ProtoManager.MaJiang_pb1 =MaJiang1_pb
ProtoManager.MaJiang_pb2 =MaJiang2_pb
ProtoManager.MaJiang_pb3 =MaJiang3_pb
ProtoManager.MaJiang_pb4 = MaJiang4_pb
ProtoManager.MaJiang_pb5 = MaJiang5_pb
ProtoManager.MAIN =MaJiang_pb.MaJiang_Proto()
ProtoManager.SUB_GAME_TABLE =MaJiang_pb.MaJiang_Proto()

ProtoManager.Log_pb=Log_pb
-- 主协议


-- 主要
ProtoManager.WebPro = Web_pb.Web_Sys()
ProtoManager.Web_pb = Web_pb
ProtoManager.LogonPro = ProtoManager.Logon_pb.Logon_Proto()  
ProtoManager.LobbyPro = ProtoManager.Lobby_pb.Lobby_Proto()  
ProtoManager.GatewayPro = ProtoManager.Gateway_pb.Gateway_Proto()  

-- 子协议
ProtoManager.Sub_GateWay = ProtoManager.Gateway_pb.Sub_GateWay() 
ProtoManager.Sub_WEB = Web_pb.Sub_WEB() 

ProtoManager.NiuNiuGame_pb  = NiuNiuGame_pb 
ProtoManager.NiuNiuGamePro = ProtoManager.NiuNiuGame_pb.NiuNiuGame_Proto()

ProtoManager.NiuNiuGame2_pb  = NiuNiuGame2_pb 
ProtoManager.NiuNiuGamePro2 = ProtoManager.NiuNiuGame2_pb.NiuNiuGame_Proto2()

ProtoManager.GaoBo_pb = GaoBo_pb
ProtoManager.GaoBoPro = ProtoManager.GaoBo_pb.GaoBo_Proto()

ProtoManager.PilotCenter_pb = PilotCenter_pb
ProtoManager.PilotCenterPro = ProtoManager.PilotCenter_pb.PilotCenter_Proto()

ProtoManager.PilotSlave_pb = PilotSlave_pb
ProtoManager.PilotSlavePro = ProtoManager.PilotSlave_pb.PilotSlave_Proto()

ProtoManager.CrossUnite_pb = CrossUnite_pb
ProtoManager.CrossUnitePro = ProtoManager.CrossUnite_pb.CrossUnite_Proto()

ProtoManager.PilotJCGame_pb = PilotJCGame_pb
ProtoManager.PilotJCGamePro = ProtoManager.PilotJCGame_pb.PilotGuessGameCMD()

ProtoManager.JCCrossUnite_pb = JCCrossUnite_pb
ProtoManager.JCCrossUnitePro = ProtoManager.JCCrossUnite_pb.JCCrossUnite_Proto()

-- 内部协议
ProtoManager.PubProto_pb = PubProto_pb
ProtoManager.PubProto_1_pb = PubProto1_pb

ProtoManager.Sys =  ProtoManager.PubProto_pb.Protocol.Sys()   
ProtoManager.Sys1 =  ProtoManager.PubProto_1_pb.Protocol1.Sys()
ProtoManager.Sub_Logon   =  ProtoManager.PubProto_pb.Protocol.Sub_Logon() 
ProtoManager.Sub_DB 	 =  ProtoManager.PubProto_pb.Protocol.Sub_DB()
ProtoManager.Sub_DB1      = ProtoManager.PubProto_1_pb.Protocol1.Sub_DB()
ProtoManager.Sub_Android =  ProtoManager.PubProto_pb.Protocol.Sub_ANDROID()
ProtoManager.Sub_LobbyGame =  ProtoManager.PubProto_pb.Protocol.Sub_LobbyGame()
ProtoManager.Sub_Control =  ProtoManager.PubProto_1_pb.Protocol1.Sub_Control() 
ProtoManager.Sub_Web =  ProtoManager.PubProto_1_pb.Protocol1.Sub_Web() 

ProtoManager.DbServer_pb =DbServer_pb
ProtoManager.DbServer1_pb =DbServer1_pb

--埋点协议
ProtoManager.Bur_pb = Buried_pb
ProtoManager.BurProto = ProtoManager.Bur_pb.BurProto()

-- 三公协议
ProtoManager.SanGongGame_pb  = SanGongGame_pb  
ProtoManager.SGProto  = ProtoManager.SanGongGame_pb.SanGongProto()  
--二八杠 
ProtoManager.ErBaGang_pb  = ErBaGang_pb  
ProtoManager.ErBaGangPro = ProtoManager.ErBaGang_pb.ErBaGang_Proto()

--百家乐 
ProtoManager.BaijialeGame_pb  = BaijialeGame_pb  
ProtoManager.BaijialeGamePro = ProtoManager.BaijialeGame_pb.BaijialeGame_Proto()

--抢庄百家乐
ProtoManager.qzBaijialeGame_pb  = qzBaijialeGame_pb  
ProtoManager.qzBaijialeGamePro = ProtoManager.qzBaijialeGame_pb.qzBaijialeGame_Proto()

--通比百家乐
ProtoManager.tbBaijialeGame_pb  = tbBaijialeGame_pb  
ProtoManager.tbBaijialeGamePro = ProtoManager.tbBaijialeGame_pb.tbBaijialeGame_Proto()

ProtoManager.MagicFace_pb = MagicFace_pb -- 魔法表情

ProtoManager.BaiRenZhaJinHua_pb =BaiRenZhaJinHua_pb --百人扎金花


ProtoManager.YuXiaXieCenter_pb= YuXiaXieCenter_pb
ProtoManager.YuXiaXieJHCenter_pb = YuXiaXieJHCenter_pb

ProtoManager.YuXiaXie_pb= YuXiaXie_pb
ProtoManager.YuXiaXiePro = ProtoManager.YuXiaXie_pb.YuXiaXie_Proto()
ProtoManager.YuXiaXie2_pb= YuXiaXie2_pb
ProtoManager.YuXiaXiePro2 = ProtoManager.YuXiaXie2_pb.YuXiaXie_Proto2()

ProtoManager.Texas_pb= Texas_pb
ProtoManager.TexasPro = ProtoManager.Texas_pb.Texas_Proto()

ProtoManager.BaiJiaLeCenter_pb=BaiJiaLeCenter_pb
ProtoManager.BaiJiaLeSlave_pb=BaiJiaLeSlave_pb
ProtoManager.BJLS_Proto = ProtoManager.BaiJiaLeSlave_pb.BJLS_Proto()

--色碟
ProtoManager.SeDie_pb = SeDie_pb
ProtoManager.SeDiePro = ProtoManager.SeDie_pb.SeDie_Proto()

--骰宝
ProtoManager.TouBaoCenter_pb= TouBaoCenter_pb
ProtoManager.TouBao_pb= TouBao_pb
ProtoManager.TBC_Proto = ProtoManager.TouBaoCenter_pb.TBC_Proto()
ProtoManager.TouBaoPro = ProtoManager.TouBao_pb.TouBao_Proto()

-- 直播主从
ProtoManager.LiveCGame_pb=LiveCGame_pb
ProtoManager.LiveCGame = ProtoManager.LiveCGame_pb.LiveCGame_Proto()
 
ProtoManager.LiveSlave_pb=LiveSlave_pb
ProtoManager.LiveSlave = ProtoManager.LiveSlave_pb.LiveSlave_Proto()
 
 
--直播色碟
ProtoManager.SeDieMCenter_pb=SeDieMCenter_pb
ProtoManager.SeDieMSlave_pb=SeDieMSlave_pb
ProtoManager.SeDieMC_Proto = ProtoManager.SeDieMCenter_pb.SeDieMC_Proto()
ProtoManager.SeDieMS_Proto = ProtoManager.SeDieMSlave_pb.SeDieMS_Proto()
 
--直播足球
ProtoManager.FootBallSlave_pb =FootBallSlave_pb
ProtoManager.FootBallCenter_pb =FootBallCenter_pb

--直播砍树
--ProtoManager.FellTreeCenter_pb = FellTreeCenter_pb
ProtoManager.FellTreeSlave_pb = FellTreeSlave_pb
--ProtoManager.FellTreeCenterPro = ProtoManager.FellTreeCenter_pb.FellTreeCenter_Proto()
ProtoManager.FellTreeSlavePro = ProtoManager.FellTreeSlave_pb.FellTreeSlave_Proto()

--俱乐部
ProtoManager.ClubCenter_pb = ClubCenter_pb
ProtoManager.ClubSlave_pb = ClubSlave_pb
ProtoManager.ClubSlave2_pb = ClubSlave2_pb
ProtoManager.DbServerClub_pb = DbServerClub_pb
ProtoManager.DbServerClub1_pb = DbServerClub1_pb

--直播篮球
--ProtoManager.BasketballCenter_pb = BasketballCenter_pb
ProtoManager.BasketballSlave_pb = BasketballSlave_pb
--ProtoManager.BasketballCenterPro = ProtoManager.BasketballCenter_pb.BasketballCenter_Proto()
ProtoManager.BasketballSlavePro = ProtoManager.BasketballSlave_pb.BasketballSlave_Proto()


ProtoManager.Chat_pb = Chat_pb

ProtoManager.ClubQZNiuNiuGame_pb  = ClubQZNiuNiuGame_pb 
ProtoManager.ClubQZNiuNiuGamePro = ProtoManager.ClubQZNiuNiuGame_pb.ClubQZNiuNiuGame_Proto()

--直播牛牛
ProtoManager.NiuNiuCenter_pb=NiuNiuCenter_pb
ProtoManager.NiuNiuSlave_pb=NiuNiuSlave_pb
ProtoManager.NNS_Proto = ProtoManager.NiuNiuSlave_pb.NNS_Proto()

-- 小游戏
ProtoManager.OldHand_pb = OldHand_pb
ProtoManager.TanQiu_pb = TanQiu_pb
ProtoManager.DiShu_pb = DiShu_pb
ProtoManager.TanXian_pb = TanXian_pb

ProtoManager.DbMiniGame_pb = DbMiniGame_pb
ProtoManager.DbMiniGame_Proto = ProtoManager.DbMiniGame_pb.DbMiniGame_Proto()


ProtoManager.AutoBet_pb = AutoBet_pb
ProtoManager.PilotSmallGame_pb = PilotSmallGame_pb



return ProtoManager