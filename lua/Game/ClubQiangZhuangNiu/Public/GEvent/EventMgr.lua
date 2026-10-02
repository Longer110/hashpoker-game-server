--[[模拟同id，多个事件触发，及1个id多个事件模型]]
package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path
local tBase    = require("base")
local tEventIo = require("EventIo")
local tSrvPub = require("SrvPublic")
local tStep = require("Step")
EventMgr = {
	tTbEvent = nil,
	tAcEvent = nil,
}

function EventMgr.Reg()
	function a(n) tBase.Log("event a"..n) end
	tBase.Log("Event register")
	EventMgr.tTbEvent = tEventIo.New()
	EventMgr.tAcEvent = tEventIo.New()
	EventMgr.tTbEvent.RegistEvent(tSrvPub.enumStep.nStartGame, tStep.WaitStartGame)
	EventMgr.tTbEvent.RegistEvent(tSrvPub.enumStep.nQiangZhuang, tStep.QiangZhuang)
	EventMgr.tTbEvent.RegistEvent(tSrvPub.enumStep.nDingZhuang, tStep.DingZhuang)
	EventMgr.tTbEvent.RegistEvent(tSrvPub.enumStep.nXiaZhu, tStep.XiaZhu)
	EventMgr.tTbEvent.RegistEvent(tSrvPub.enumStep.nShouPai, tStep.ShouPai)
	EventMgr.tTbEvent.RegistEvent(tSrvPub.enumStep.nFaPai, tStep.FaPai)
	EventMgr.tTbEvent.RegistEvent(tSrvPub.enumStep.nTanPaiReady, tStep.TanPaiReady)
	EventMgr.tTbEvent.RegistEvent(tSrvPub.enumStep.nTanPai, tStep.TanPai)

	EventMgr.tTbEvent.RegistEvent(tSrvPub.enumStep.nJieSuan, tStep.CaleScore)
	EventMgr.tTbEvent.RegistEvent(tSrvPub.enumStep.nReset, tStep.Reset)
end

return EventMgr

