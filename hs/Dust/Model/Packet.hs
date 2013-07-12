module Dust.Model.Packet
(
    IP(..),
    Transport(..),
    Packet(..),
    parsePacket
)
where

import Data.ByteString (ByteString, unpack)
import Data.Binary.Strict.Get
import qualified Data.ByteString as B
import Data.Int
import Data.Word
import System.Directory
import Data.List (nub)
import Data.Map (Map(..), alter, empty)
import Data.Bits

import Dust.Model.PacketLength
import qualified Dust.Model.Content as C
import Dust.Model.Port
import Dust.Model.TrafficModel

data Ethernet = Ethernet {
  ethDest :: ByteString, -- 6 bytes
  ethSrc  :: ByteString, -- 6 bytes
  ethtype :: Word16
} deriving (Show)

parseEthernet :: ByteString -> (Either String Ethernet, ByteString)
parseEthernet bs = runGet getEthernet bs

getEthernet :: Get Ethernet
getEthernet = do
  bs0 <- getByteString 6
  bs7 <- getByteString 6
  s13 <- getWord16be

  return $ Ethernet bs0 bs7 s13

data IP  = IP {
  version :: Word8,
  ihl     :: Word8,
  tos     :: Word8,
  tl      :: Word16,
  id      :: Word16,
  ipflags :: Word8,
  fragment:: Word16,
  ttl     :: Word8,
  prot    :: Word8,
  checksum:: Word16,
  source  :: Word32,
  dest    :: Word32,
  ipopts  :: ByteString
} deriving (Show)

parseIP :: ByteString -> (Either String IP, ByteString)
parseIP bs = runGet getIP bs

getIP :: Get IP
getIP = do
  b0 <- getWord8
  b1 <- getWord8
  s2 <- getWord16be
  s4 <- getWord16be
  s6 <- getWord16be
  b8 <- getWord8
  b9 <- getWord8
  s10<- getWord16be
  l12<- getWord32be
  l14<- getWord32be
  let v20 = B.empty

  let v = shift b0 (-4)
  let hl = shift (shift b0 4) (-4)
  let f = (fromIntegral $ shift s6 (-13))::Word8
  let fo = shift (shift s6 3) (-3)
  
  return $ IP v hl b1 s2 s4 f fo b8 b9 s10 l12 l14 v20

data Transport = 
  TCP {
    srcport :: Word16,
    destport:: Word16,
    seqnum  :: Word32,
    acknum  :: Word32,
    offset  :: Word8,
    reserved:: Word8,
    tcpflags:: Word8,
    window  :: Word16,
    tcpchk  :: Word16,
    urgent  :: Word16,
    tcptops :: ByteString
  } 
  | UDP {
    srcport :: Word16,
    destport:: Word16,
    len     :: Word16,
    udpchk  :: Word16
  }
  deriving (Show)

parseTCP :: ByteString -> (Either String Transport, ByteString)
parseTCP bs = runGet getTCP bs

getTCP :: Get Transport
getTCP = do
  s0 <- getWord16be
  s2 <- getWord16be
  l4 <- getWord32be
  l8 <- getWord32be
  b12<- getWord8
  b13<- getWord8
  s14<- getWord16be
  s16<- getWord16be
  s18<- getWord16be

  let off = shift b12 (-4)
  let rsv = shift (shift b12 4) (-4)
  
  v20 <- getByteString (fromIntegral ((off - 5) * 4)::Int)

  return $ TCP s0 s2 l4 l8 off rsv b13 s14 s16 s18 v20

parseUDP :: ByteString -> (Either String Transport, ByteString)
parseUDP bs = runGet getUDP bs

getUDP :: Get Transport
getUDP = do
  s0 <- getWord16be
  s2 <- getWord16be
  s4 <- getWord16be
  s6 <- getWord16be

  return $ UDP s0 s2 s4 s6

data Packet = Packet Ethernet IP Transport ByteString deriving (Show)

parsePacket :: ByteString -> (Either String Packet)
parsePacket bs =
  let (eitherEther, noether) = parseEthernet bs
  in case eitherEther of
    Left etherError -> Left etherError
    Right ether -> let (eitherIP, noip) = parseIP noether
      in case eitherIP of
        Left ipError -> Left ipError
        Right ip -> case (prot ip) of
          6  -> let (eitherTCP, notcp) = parseTCP noip
            in case eitherTCP of
              Left tcpError -> Left tcpError
              Right tcp -> Right $ Packet ether ip tcp notcp
          17 -> let (eitherUDP, noudp) = parseUDP noip
            in case eitherUDP of
              Left udpError -> Left udpError
              Right udp -> Right $ Packet ether ip udp noudp
          otherwise -> Left $ "Unknown protocol " ++ (show $ prot ip)
