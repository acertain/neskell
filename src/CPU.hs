
--{-# LANGUAGE RankNTypes #-}
--{-# LANGUAGE GeneralizedNewtypeDeriving  #-}

module CPU ( runEmulator
           , TerminationCond(..)
           ) where

import Instruction

import qualified Data.Vector.Unboxed.Mutable as VUM
import qualified Data.ByteString as B
import Data.Word (Word8, Word16, Word64)
import Control.Monad (unless)

--import Control.Applicative ((<$>))
import Control.Monad.ST (ST, runST)
import Data.STRef

import Control.Monad.Reader (ReaderT, asks, runReaderT)
import Control.Monad.Trans (lift)

data CPUState s = CPUState
    { cpuRAM   :: VUM.MVector s Word8
    , cpuPC    :: STRef s Word16
    , cpuA     :: STRef s Word8
    , cpuX     :: STRef s Word8
    , cpuY     :: STRef s Word8
    , cpuSR    :: STRef s Word8
    , cpuSP    :: STRef s Word8
    , cpuCycle :: STRef s Word64
    }

type RSTEmu s a = ReaderT (CPUState s) (ST s) a

{-
class (Functor m, Monad m) => MonadEmulator m where
    dummy :: Int -> m ()
    --load  :: Address -> m Word16
    --store :: Address -> Word16 -> m ()

instance MonadEmulator (RSTEmu s) where
    dummy _ = return ()
-}

data TerminationCond = TermNever | TermOnPC Word16 | TermOnOpC OpCode | TermOnCycleGT Word64

checkTC :: TerminationCond -> RSTEmu s Bool
checkTC tc =
    case tc of
        TermNever       -> return False
        TermOnPC pc     -> return False
        TermOnOpC opc   -> return False
        TermOnCycleGT c -> return False

runCPU :: TerminationCond -> RSTEmu s ()
runCPU tc = do
    let loop = do
            terminate <- checkTC tc
            unless terminate loop
     in loop

loadBinary :: B.ByteString -> Word16 -> RSTEmu s ()
loadBinary bin offs = do
    ram <- asks cpuRAM
    mapM_ (\i -> lift $
        VUM.write ram (fromIntegral offs + i) $
        B.index   bin (fromIntegral offs + i)) [0..B.length bin]

runEmulator :: B.ByteString -> Word16 -> Word16 -> TerminationCond -> Int
runEmulator bin offs pc tc =
    runST $ do
        initRAM   <- VUM.replicate (2 ^ (16 :: Int)) (0 :: Word8)
        initPC    <- newSTRef pc
        initA     <- newSTRef 0
        initX     <- newSTRef 0
        initY     <- newSTRef 0
        initSR    <- newSTRef 0
        initSP    <- newSTRef 0xFF
        initCycle <- newSTRef 0
        let cpu = CPUState
                  { cpuRAM   = initRAM
                  , cpuPC    = initPC
                  , cpuA     = initA
                  , cpuX     = initX
                  , cpuY     = initY
                  , cpuSR    = initSR
                  , cpuSP    = initSP
                  , cpuCycle = initCycle
                  }
        runReaderT (do
            loadBinary bin offs
            runCPU tc) cpu
        return 0

