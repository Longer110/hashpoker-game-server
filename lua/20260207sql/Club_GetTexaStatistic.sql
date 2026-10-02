DROP PROCEDURE IF EXISTS `Club_GetTexaStatistic`;
DELIMITER $$

CREATE PROCEDURE `Club_GetTexaStatistic`(IN `nUserId` int,IN `nGameId` int,IN `nGoldType` int,IN `nClubId` int)
BEGIN
	DECLARE PaiJuCnt INT DEFAULT 0;   
	DECLARE nClubId1 INT DEFAULT 0; 
	DECLARE AllInAndWinCount DOUBLE DEFAULT 0;     
	IF nClubId=-1 THEN
		IF nGoldType=1 THEN
			SELECT COUNT(*) INTO PaiJuCnt FROM DJH_RecordDB.ClubTableUserInfo WHERE UserId=nUserId AND ItemId=1 AND GameId=nGameId;
      SELECT ROUND(SUM(HandProfit - InsureBuy - Penalty + InsureWin + Revenue), 2) INTO AllInAndWinCount from PaiJuWinLoseRecord WHERE UserID=nUserId AND GoldType=1 AND GameType=nGameId;
		ELSEIF nGoldType=2 THEN
			SELECT COUNT(*) INTO PaiJuCnt FROM DJH_RecordDB.ClubTableUserInfo WHERE UserId=nUserId AND ItemId>=1000000 AND GameId=nGameId;
      SELECT ROUND(SUM(HandProfit - InsureBuy - Penalty + InsureWin + Revenue), 2) INTO AllInAndWinCount from PaiJuWinLoseRecord WHERE UserID=nUserId AND GoldType>=1000000 AND GameType=nGameId;
		END IF;
		SELECT 
			SUM(PlayCount) AS PlayCount,
			SUM(InPoolCount) AS InPoolCount,
			SUM(RaiseCountBFlop) AS RaiseCountBFlop,
			SUM(AllInAndWinCount) AS AllInAndWinCount,
			SUM(AllInCount) AS AllInCount,
			SUM(HandProfit) AS ProfitSum,
			PaiJuCnt, -- 如果PaiJuCnt是一个唯一值，可以使用MAX
			SUM(WinCount) AS WinCount,
			SUM(QiPaiCount) AS QiPaiCount,
			SUM(HandProfit) AS HandProfit,
            SUM(SeeFlop) AS SeeFlop,
            SUM(ReachShowdown) AS ReachShowdown
		FROM 
			DJH_RecordDB.TexaClubUserStatistic 
		WHERE 
			UserId = nUserId AND 
			GameId = nGameId AND 
			GoldType = nGoldType;
	ELSE
		IF nGoldType=1 THEN
			SELECT COUNT(*) INTO PaiJuCnt FROM DJH_RecordDB.ClubTableUserInfo WHERE UserId=nUserId AND ItemId=1 AND GameId=nGameId AND ClubId=nClubId;
      SELECT ROUND(SUM(HandProfit - InsureBuy - Penalty + InsureWin + Revenue), 2) INTO AllInAndWinCount from PaiJuWinLoseRecord WHERE UserID=nUserId AND GoldType=1 AND GameType=nGameId AND ClubId=nClubId;
		ELSEIF nGoldType=2 THEN
			SELECT COUNT(*) INTO PaiJuCnt FROM DJH_RecordDB.ClubTableUserInfo WHERE UserId=nUserId AND ItemId>=1000000 AND GameId=nGameId AND ClubId=nClubId;
      SELECT ROUND(SUM(HandProfit - InsureBuy - Penalty + InsureWin + Revenue), 2) INTO AllInAndWinCount from PaiJuWinLoseRecord WHERE UserID=nUserId AND GoldType>=1000000 AND GameType=nGameId AND ClubId=nClubId;
		END IF;
		IF nClubId < 1000000 THEN
			SET nClubId1 = nClubId;
		ELSE
			SET nClubId1 = nClubId;
		END IF;
        SELECT 
			SUM(PlayCount) AS PlayCount,
			SUM(InPoolCount) AS InPoolCount,
			SUM(RaiseCountBFlop) AS RaiseCountBFlop,
			AllInAndWinCount,
			SUM(AllInCount) AS AllInCount,
			SUM(HandProfit) AS ProfitSum,
			PaiJuCnt, -- 如果PaiJuCnt是一个唯一值，可以使用MAX
			SUM(WinCount) AS WinCount,
			SUM(QiPaiCount) AS QiPaiCount,
			SUM(HandProfit) AS HandProfit,
            SUM(SeeFlop) AS SeeFlop,
            SUM(ReachShowdown) AS ReachShowdown
		FROM 
			DJH_RecordDB.TexaClubUserStatistic 
		WHERE 
			UserId = nUserId AND 
			GameId = nGameId AND 
			GoldType = nGoldType AND ClubId=nClubId1;
	END IF;
END $$

DELIMITER ;
