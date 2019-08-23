#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2019 Bitcoin Suisse
#
# SPDX-License-Identifier: LicenseRef-Proprietary
#

@test "invoking tzbtc 'approve' command" {
  result="$(stack exec -- tzbtc approve\
          --spender "tz1MuPWVNHwcqLXdJ5UWcjvTHiaAMocaZisx" --value 100)"
  [ "$result" == '(Left (Left (Left (Right (Pair "tz1MuPWVNHwcqLXdJ5UWcjvTHiaAMocaZisx" 100)))))' ]
}

@test "invoking tzbtc 'mint' command" {
  result="$(stack exec -- tzbtc mint\
          --to "tz1MuPWVNHwcqLXdJ5UWcjvTHiaAMocaZisx" --value 100)"
  [ "$result" == '(Left (Right (Right (Right (Right (Pair "tz1MuPWVNHwcqLXdJ5UWcjvTHiaAMocaZisx" 100))))))' ]
}

@test "invoking tzbtc 'burn' command" {
  result="$(stack exec -- tzbtc burn --from "tz1MuPWVNHwcqLXdJ5UWcjvTHiaAMocaZisx" --value 100)"
  [ "$result" == '(Right (Left (Left (Left (Pair "tz1MuPWVNHwcqLXdJ5UWcjvTHiaAMocaZisx" 100)))))' ]
}

@test "invoking tzbtc 'transfer' command" {
  result="$(stack exec -- tzbtc transfer\
    --to "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV"\
    --from "tz1MuPWVNHwcqLXdJ5UWcjvTHiaAMocaZisx" --value 100)"
  [ "$result" == '(Left (Left (Left (Left (Pair "tz1MuPWVNHwcqLXdJ5UWcjvTHiaAMocaZisx" (Pair "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV" 100))))))' ]
}

@test "invoking tzbtc 'getAllowance' command" {
  result="$(stack exec -- tzbtc getAllowance\
    --owner "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV"\
    --spender "tz1MuPWVNHwcqLXdJ5UWcjvTHiaAMocaZisx"\
    --callback "KT1SyriCZ2kDyEMJ6BtQecGkFqVciQcfWj46")"
  [ "$result" == '(Left (Left (Right (Left (Pair (Pair "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV" "tz1MuPWVNHwcqLXdJ5UWcjvTHiaAMocaZisx") "KT1SyriCZ2kDyEMJ6BtQecGkFqVciQcfWj46")))))' ]
}

@test "invoking tzbtc 'getBalance' command" {
  result="$(stack exec -- tzbtc getBalance\
    --address "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV"\
    --callback "KT1SyriCZ2kDyEMJ6BtQecGkFqVciQcfWj46")"
  [ "$result" == '(Left (Left (Right (Right (Pair "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV" "KT1SyriCZ2kDyEMJ6BtQecGkFqVciQcfWj46")))))' ]
}

@test "invoking tzbtc 'addOperator' command" {
  result="$(stack exec -- tzbtc addOperator\
    --operator "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV")"
  [ "$result" == '(Right (Left (Left (Right "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV"))))' ]
}

@test "invoking tzbtc 'removeOperator' command" {
  result="$(stack exec -- tzbtc removeOperator\
    --operator "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV")"
  [ "$result" == '(Right (Left (Right (Left "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV"))))' ]
}

@test "invoking tzbtc 'pause' command" {
  result="$(stack exec -- tzbtc pause)"
  [ "$result" == '(Right (Left (Right (Right (Right True)))))' ]
}

@test "invoking tzbtc 'unpause' command" {
  result="$(stack exec -- tzbtc unpause)"
  [ "$result" == '(Right (Left (Right (Right (Right False)))))' ]
}

@test "invoking tzbtc 'setRedeemAddress' command" {
  result="$(stack exec -- tzbtc setRedeemAddress "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV")"
  [ "$result" == '(Right (Left (Right (Right (Left "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV")))))' ]
}

@test "invoking tzbtc 'startMigrateFrom' command" {
  result="$(stack exec -- tzbtc startMigrateFrom "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV")"
  [ "$result" == '(Right (Right (Right (Right (Left "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV")))))' ]
}

@test "invoking tzbtc 'startMigrateTo' command" {
  result="$(stack exec -- tzbtc startMigrateTo "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV")"
  [ "$result" == '(Right (Right (Right (Left "tz1UMD9BcyJsiTrPLQSy1yoYzBhKUry66wRV"))))' ]
}

@test "invoking tzbtc 'migrate' command" {
  result="$(stack exec -- tzbtc migrate)"
  [ "$result" == '(Right (Right (Right (Right (Right Unit)))))' ]
}

@test "invoking tzbtc 'printContract' command" {
  stack exec -- tzbtc printContract
}

@test "invoking tzbtc 'printContract' command with --oneline flag" {
  stack exec -- tzbtc printContract --oneline
}
