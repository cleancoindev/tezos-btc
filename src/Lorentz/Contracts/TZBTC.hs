{- SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-Proprietary
 -}
{-# LANGUAGE RebindableSyntax #-}
{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}

module Lorentz.Contracts.TZBTC
  ( mkStorage
  , Parameter(..)
  , Storage
  , tzbtcContract
  ) where

import Fmt (Buildable(..), (+|), (|+))

import Lorentz

import Lorentz.Contracts.TZBTC.Impl
import Lorentz.Contracts.TZBTC.Types

{-# ANN module ("HLint: ignore Reduce duplication" :: Text) #-}

----------------------------------------------------------------------------
-- Parameter
----------------------------------------------------------------------------

data Parameter
  = Transfer            !TransferParams
  | Approve             !ApproveParams
  | GetAllowance        !(View GetAllowanceParams Natural)
  | GetBalance          !(View Address Natural)
  | GetTotalSupply      !(View () Natural)
  | SetPause            !Bool
  | SetAdministrator    !Address
  | GetAdministrator    !(View () Address)
  | Mint                !MintParams
  | Burn                !BurnParams
  | AddOperator         !OperatorParams
  | RemoveOperator      !OperatorParams
  | SetRedeemAddress    !SetRedeemAddressParams
  | Pause               !PauseParams
  | TransferOwnership   !TransferOwnershipParams
  | AcceptOwnership     !AcceptOwnershipParams
  | StartMigrateTo      !StartMigrateToParams
  | StartMigrateFrom    !StartMigrateFromParams
  | Migrate             !MigrateParams
  deriving stock Generic
  deriving anyclass IsoValue


instance Buildable Parameter where
  build = \case
    Transfer (arg #from -> from, arg #to -> to, arg #value -> value) ->
      "Transfer from " +| from |+ " to " +| to |+ ", value = " +| value |+ ""
    Approve (arg #spender -> spender, arg #value -> value) ->
      "Approve for " +| spender |+ ", value = " +| value |+ ""
    GetAllowance (View (arg #owner -> owner, arg #spender -> spender) _) ->
      "Get allowance for " +| owner |+ " from " +| spender |+ ""
    GetBalance (View addr _) ->
      "Get balance for " +| addr |+ ""
    GetTotalSupply _ ->
      "Get total supply"
    SetPause b ->
      "Set pause to " +| b |+ ""
    SetAdministrator addr ->
      "Set administrator to " +| addr |+ ""
    GetAdministrator _ ->
      "Get administrator"
    Mint (arg #to -> to, arg #value -> value) ->
      "Mint to " +| to |+ ", value = " +| value |+ ""
    Burn (arg #from -> from, arg #value -> value) ->
      "Burn from " +| from |+ ", value = " +| value |+ ""
    AddOperator (arg #operator -> operator) ->
      "Add operator " +| operator |+ ""
    RemoveOperator (arg #operator -> operator) ->
      "Remove operator " +| operator |+ ""
    SetRedeemAddress (arg #redeem -> redeem) ->
      "Set redeem address to " +| redeem |+ ""
    Pause b ->
      "Pause " +| b |+ ""
    TransferOwnership (arg #newowner -> newOwner) ->
      "Transfer ownership to " +| newOwner |+ ""
    AcceptOwnership _ ->
      "Accept ownership"
    StartMigrateTo (arg #migrateto -> migrateTo) ->
      "Start migrate to " +| migrateTo |+ ""
    StartMigrateFrom (arg #migratefrom -> migrateFrom) ->
      "Start migrate from " +| migrateFrom |+ ""
    Migrate _ ->
      "Migrate"

----------------------------------------------------------------------------
-- Implementation
----------------------------------------------------------------------------


tzbtcContract :: Contract Parameter Storage
tzbtcContract = do
  unpair
  caseT @Parameter
    ( #cTransfer /-> transfer
    , #cApprove /-> approve
    , #cGetAllowance /-> getAllowance
    , #cGetBalance /-> getBalance
    , #cGetTotalSupply /-> getTotalSupply
    , #cSetPause /-> setPause
    , #cSetAdministrator /-> setAdministrator
    , #cGetAdministrator /-> getAdministrator
    , #cMint /-> mint
    , #cBurn /-> burn
    , #cAddOperator /-> addOperator
    , #cRemoveOperator /-> removeOperator
    , #cSetRedeemAddress /-> setRedeemAddress
    , #cPause /-> setPause
    , #cTransferOwnership /-> transferOwnership
    , #cAcceptOwnership /-> acceptOwnership
    , #cStartMigrateTo /-> startMigrateTo
    , #cStartMigrateFrom /-> startMigrateFrom
    , #cMigrate /-> migrate
    )