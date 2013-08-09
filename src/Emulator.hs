
module Emulator ( runEmulator
                , Cond(..)
                ) where

-- Emulator main loop. Load a binary, set up the CPU and then run until a
-- termination criterea has been met

import Util
import MonadEmulator
import Execution
import qualified Instruction as I

import qualified Data.ByteString as B
import Data.Word (Word8, Word16, Word64)
import Control.Monad (unless, filterM)
import Control.Applicative ((<$>))
import Text.Printf

data Cond =
      CondLS     LoadStore Word8 -- Compare any memory address / CPU state to
    | CondOpC    I.OpCode        -- PC pointing to a specific opcode
    | CondCycleR Word64 Word64   -- Cycle count in the specified closed interval

instance Show Cond where
    show (CondLS ls w   ) = printf "%s == 0x%02X" (show ls) w
    show (CondOpC opc   ) = "OpCode(PC) == " ++ show opc
    show (CondCycleR l h) = unlines ["cycle E [", show l, show h, "]"]

checkCond :: MonadEmulator m => Cond -> m Bool
checkCond cond =
    case cond of
        CondLS     ls w -> (== w) <$> load ls
        CondOpC    opc  -> do (I.Instruction decOpC _) <- I.decodeInstructionM
                              return $ decOpC == opc
        CondCycleR l h  -> undefined -- TODO

loadBinary :: MonadEmulator m => B.ByteString -> Word16 -> m ()
loadBinary bin offs = do
    mapM_ (\i -> store (Addr $ offs + fromIntegral i) $
                 B.index bin i)
          [0..B.length bin - 1]

runEmulator ::
    [(B.ByteString, Word16)] -> -- List of program binaries and their offsets
    [(LoadStore, Word8)]     -> -- Store operations to set up simulator state
    [Cond]                   -> -- The simulator will stop when all of these conditions are met
    [Cond]                   -> -- Conditions to verify once stopped
    Bool                     -> -- Enable execution tracing
    ( [Cond]                    -- Conditions which were not met
    , String                    -- Debug string of last CPU state
    , B.ByteString              -- Execution trace
    )
runEmulator bins setup stopc verc trace =
    runSTEmulator trace $ do
        mapM_ (\(bin, offs) -> loadBinary bin offs) bins
        mapM_ (\(ls, w8)    -> store ls w8) setup
        store SP 0xFF
        store SR . setFlag FI . setFlag F1 $ 0
        let loop = do
                stop <- and <$> mapM (checkCond) stopc
                inst <- I.decodeInstructionM
                execute inst
                unless stop loop
         in do
                loop
                cond     <- filterM (\x -> not <$> checkCond x) verc
                cpust    <- cpuState
                cputrace <- getTrace
                return (cond, cpust, cputrace)
