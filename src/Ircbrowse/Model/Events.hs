module Ircbrowse.Model.Events where

import Ircbrowse.Types
import Ircbrowse.Data
import Ircbrowse.Monads
import Ircbrowse.Tunes

import Data.Text (Text)
import Snap.App
import Sphinx
import Text.Blaze.Pagination

getEvents :: Channel -> Maybe Integer -> PN -> Maybe Text
          -> Model c s (Pagination,[Event])
getEvents channel tid (PN _ pagination _) q = do
  case q of
    Just q -> do
      result <- io $ search def
        { sPath = "/opt/sphinx/bin/search"
        , sConfig = "sphinx.conf"
        , sQuery = escapeText q
        , sOffset = fromIntegral ((pnCurrentPage pagination - 1) * pnPerPage pagination)
        , sLimit = fromIntegral (pnPerPage pagination)
        , sFilters = [("channel",showChanInt channel)]
        }
      case result of
        Left err -> do io $ appendFile "/tmp/sphinx-error.log" (err ++"\n")
                       return (pagination { pnTotal = 0 },[])
        Right result -> do
          results <- getEventsByResults channel (map fst (rResults result))
          return (pagination { pnTotal = fromIntegral (rTotal result) }
                 ,results)
    Nothing -> do
      case tid of
        Nothing -> getPaginatedEvents channel pagination
        Just t -> getTimestampedEvents channel t pagination

getEventsByResults :: Channel -> [Int] -> Model c s [Event]
getEventsByResults channel eids = do
  query ["SELECT (SELECT id FROM event_order_index WHERE origin = event.id),"
        ,"timestamp,network,channel,type,nick,text"
        ,"FROM event"
        ,"WHERE id IN ("
        ,intercalate ", " (map show eids)
        ,") ORDER BY timestamp DESC"]
        ()

getTimestampedEvents channel tid pagination = do
  getPaginatedEvents channel pagination { pnCurrentPage = tid `div` pnPerPage pagination + 1 }

getPaginatedEvents channel pagination = do
  count <- single ["SELECT count FROM event_count where channel = ?"] (Only (showChanInt channel))
  now <- io getCurrentTime
  events <- query ["SELECT id,timestamp,network,channel,type,nick,text FROM event"
                  ,"WHERE id in (SELECT origin FROM event_order_index WHERE idx = ? and id >= ? and id < ? LIMIT ?)"
                  ,"ORDER BY timestamp ASC"
                  ,"LIMIT ?"]
                  (idxNum channel
                  ,offset
                  ,offset + limit
                  ,limit
                  ,limit)
  after <- io getCurrentTime
  return (pagination { pnTotal = fromMaybe 0 count }
         ,events)

  where offset = 1 + (max 0 (pnCurrentPage pagination - 1) * pnPerPage pagination)
        limit = pnPerPage pagination

idxNum :: Channel -> Int
idxNum Lisp = 2000
idxNum Haskell = 1000
