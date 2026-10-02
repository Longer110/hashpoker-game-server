-------------------------------------------------------------------------------
-- Saves logging information in a file
--
-- @author Thiago Costa Ponte (thiago@ideais.com.br)
--
-- @copyright 2004-2007 Kepler Project
--
-- @release $Id: file.lua,v 1.5 2007/09/05 12:15:31 tomas Exp $
-------------------------------------------------------------------------------

require"logging"

function logging.file(logDir, logtype, mLog)

    mLog.SetLogPath(logDir, logtype)

    return logging.new( function(self, level, message)
                            mLog.Log('['..level..']'..message)
                            return true
                        end
                      )
end
