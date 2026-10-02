DROP PROCEDURE IF EXISTS `Club_GetTexasTableDetail`;
DELIMITER $$

CREATE PROCEDURE `Club_GetTexasTableDetail`(IN `sTableId` VARCHAR(50))
BEGIN
    DECLARE nLiverUserId INT DEFAULT 0;   
    DECLARE sLiverFaceId VARCHAR(200) DEFAULT "";   
    DECLARE sLiverName VARCHAR(200) DEFAULT "";   
    DECLARE nMVPUserId INT DEFAULT 0;   
    DECLARE sMVPFaceId VARCHAR(200) DEFAULT "";   
    DECLARE sMVPName VARCHAR(200) DEFAULT "";   
    DECLARE nTHUserId INT DEFAULT 0;   
    DECLARE sTHFaceId VARCHAR(200) DEFAULT "";   
    DECLARE sTHName VARCHAR(200) DEFAULT "";   
    DECLARE nDYUserId INT DEFAULT 0;   
    DECLARE sDYFaceId VARCHAR(200) DEFAULT "";   
    DECLARE sDYName VARCHAR(200) DEFAULT "";   
    DECLARE nHandCnt INT DEFAULT 0;   
    DECLARE nTakeIn DOUBLE DEFAULT 0;   
    DECLARE nJournalAccount DOUBLE DEFAULT 0;   
    DECLARE nMaxPool DOUBLE DEFAULT 0;   
    DECLARE nInsurancePool DOUBLE DEFAULT 0;   
    DECLARE sTime DATETIME;   
    DECLARE nKeepTime INT DEFAULT 0;   
    DECLARE sTableInfo VARCHAR(2048) DEFAULT "";   
    DECLARE sCreateTime DATETIME;   
    DECLARE nSumBet DOUBLE DEFAULT 0;   

    SELECT LiveUserId, KeepSec, TableInfo, EndTime, CreateTime
    INTO nLiverUserId, nKeepTime, sTableInfo, sTime, sCreateTime
    FROM DJH_RecordDB.ClubTableRecord
    WHERE TableId = sTableId;

    SELECT FaceID, NickName
    INTO sLiverFaceId, sLiverName
    FROM DJH_AccountsDB.Accounts_InFo
    WHERE UserID = nLiverUserId;

    SELECT UserId, FaceId, NickName
    INTO nMVPUserId, sMVPFaceId, sMVPName
    FROM DJH_RecordDB.TexaTableUserStatistic
    WHERE TableId = sTableId
    ORDER BY ProfitSum DESC
    LIMIT 1;

    SELECT UserId, FaceId, NickName
    INTO nTHUserId, sTHFaceId, sTHName
    FROM DJH_RecordDB.TexaTableUserStatistic
    WHERE TableId = sTableId
    ORDER BY TakeInTotal DESC
    LIMIT 1;

    SELECT UserId, FaceId, NickName
    INTO nDYUserId, sDYFaceId, sDYName
    FROM DJH_RecordDB.TexaTableUserStatistic
    WHERE TableId = sTableId
    ORDER BY ProfitSum ASC
    LIMIT 1;

    SELECT PlayCount, FlowTotal, PoolMax, InsurPool, SumBet
    INTO nHandCnt, nJournalAccount, nMaxPool, nInsurancePool, nSumBet
    FROM DJH_RecordDB.TexaTableStatistic
    WHERE TableId = sTableId;

    SELECT ROUND(IFNULL(SUM(u.LockGold), 0), 2)
    INTO nTakeIn
    FROM DJH_RecordDB.UserLockGoldRecord u
    INNER JOIN DJH_RecordDB.TexaTableUserStatistic t
        ON t.UserId = u.UserId AND t.TableId = u.TableId
    WHERE u.TableId = sTableId;

    IF sTime IS NULL THEN
        IF nKeepTime <> -1 AND DATE_ADD(sCreateTime, INTERVAL nKeepTime SECOND) < NOW() THEN
            SET sTime = DATE_ADD(sCreateTime, INTERVAL nKeepTime SECOND);
        ELSE
            SET sTime = NOW();
        END IF;
    END IF;

    SELECT
        nLiverUserId,
        sLiverFaceId,
        sLiverName,
        nMVPUserId,
        sMVPFaceId,
        sMVPName,
        nTHUserId,
        sTHFaceId,
        sTHName,
        nDYUserId,
        sDYFaceId,
        sDYName,
        nHandCnt,
        nTakeIn,
        nJournalAccount,
        nMaxPool,
        nInsurancePool,
        sTime,
        nKeepTime,
        sTableInfo,
        nSumBet;

END $$

DELIMITER ;