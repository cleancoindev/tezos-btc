{- SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-Proprietary
 -}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-missing-signatures #-}

module Test.IO
  ( test_dryRunFlag
  , test_setupClient
  , test_setupClientTemplate
  , test_setupClientTemplateFull
  , test_createMultisigPackage
  , test_multisigSignPackage
  , test_multisigExecutePackage
  ) where

import Data.Aeson (encode, decode)
import qualified Data.Map as Map
import qualified Data.Text as T
import qualified Data.Typeable as Typ (cast)
import Text.Hex (decodeHex)
import Options.Applicative (ParserResult(..), defaultPrefs, execParserPure)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertFailure, testCase)
import Util.Named

import Client.IO (mainProgram)
import Client.Error
import Client.Types
import Client.Util
import qualified Lorentz.Contracts.TZBTC.MultiSig as MS
import qualified Lorentz.Contracts.TZBTC as TZBTC
import qualified Lorentz.Contracts.TZBTC.Types as TZBTCTypes
import Michelson.Typed.Haskell.Value (fromVal, toVal)
import Tezos.Address
import Tezos.Crypto
import Util.AbstractIO
import Util.MultiSig

{-# ANN module ("HLint: ignore Reduce duplication" :: Text) #-}

instance MonadFail (Either SomeException) where
  fail s = Left $ toException $ TestError s

-- Some configuration values to configure the
-- base/default mock behavior.
data MockInput = MockInput
  { miCmdLine :: [String]
  , miConfig :: ClientConfig
  , miConfigPaths :: (DirPath, FilePath)
  }

defaultMockInput = MockInput
  { miCmdLine = []
  , miConfig = ClientConfig
     { ccNodeAddress = "localhost"
     , ccNodePort = 2990
     , ccNodeUseHttps = False
     , ccContractAddress = Just contractAddress
     , ccMultisigAddress = Nothing
     , ccUserAlias = "bob"
     , ccTezosClientExecutable = "tezos-client"
     }
  , miConfigPaths = (DirPath configDir, configPath)
  }

-- | The default mock handlers that indvidual tests could
-- override.
defaultHandlers :: MockInput -> Handlers TestM
defaultHandlers mi = Handlers
  { hWriteFileUtf8 = \_ _ -> unavailable "writeFileUtf8"
  , hWriteFile = \_ _ -> unavailable "writeFile"
  , hReadFile  = \_ -> unavailable "readFile"
  , hDoesFileExist  = \_ -> unavailable "doesFileExist"
  , hDecodeFileStrict = \_ -> unavailable "decodeFileStrict"
  , hCreateDirectoryIfMissing = \_ _ -> unavailable "createDirectoryIfMissing"
  , hGetConfigPaths = do
      removeExpectation GetConfigPaths
      pure $ miConfigPaths mi
  , hReadConfig = do
      removeExpectation ReadConfig
      pure $ Right $ miConfig mi
  , hReadConfigText = unavailable "readConfigText"
  , hWriteConfigFull = \_ -> unavailable "writeConfigFull"
  , hWriteConfigPartial = \_ -> unavailable "writeConfigPartial"
  , hWriteConfigText = \_ -> unavailable "writeConfigText"
  , hParseCmdLine = \p -> do
      case execParserPure defaultPrefs p (miCmdLine mi) of
        Success a -> do
          removeExpectation ParseCmdLine
          pure a
        Failure _ -> throwM $ TestError "CMDline parsing failed"
        _ -> throwM $ TestError "Unexpected cmd line autocompletion"
  , hPrintStringLn = \_ -> removeExpectation PrintsMessage
  , hPrintTextLn = \_ -> removeExpectation PrintsMessage
  , hPrintByteString = \_ -> unavailable "printByteString"
  , hGetLineFromUser = unavailable "getLineFromUser"
  , hRunTransactions = \_ _ -> unavailable "runTransactions"
  , hGetStorage = \_ -> unavailable "getStorage"
  , hGetCounter = \_ -> unavailable "getCounter"
  , hGetFromBigMap = \_ _ -> unavailable "getFromBigMap"
  , hWaitForOperation = \_ -> unavailable "waitForOperation"
  , hDeployTzbtcContract = \_ _ -> unavailable "deployTzbtcContract"
  , hGetAddressAndPKForAlias = \_ -> unavailable "getAddressAndPKForAlias"
  , hSignWithTezosClient = \_ -> unavailable "signWithTezosClient"
  , hOpenEditor = \_ _ -> unavailable "openEditor"
  }
  where
    unavailable :: String -> TestM a
    unavailable msg = throwM $ TestError $ "Unexpected method call : " <> msg

-- | Run a test using the given mock handlers in TestM
runMock :: forall a . Handlers TestM -> TestM a -> Assertion
runMock h m = case runReaderT (runStateT m Map.empty) (MyHandlers h) of
  Right _ -> pass
  Left e -> assertFailure $ displayException e

-- | Add a test expectation
addExpectation :: (MonadState ST m) => Expectation -> ExpectationCount -> m ()
addExpectation s i = state (\m -> ((), Map.insert s (ExpectationStatus i 0)  m))

-- | Meet a previously set expectation
removeExpectation :: forall m. (MonadThrow m, MonadState ST m) => Expectation -> m ()
removeExpectation s = do
  m <- get
  case Map.lookup s m of
    Just es -> put $ Map.insert s (es { exOccurCount = exOccurCount es + 1 }) m
    Nothing  -> throwM $ TestError $ "Unset expectation:" ++ show s

-- | Check if all the expectation have been met.
checkExpectations :: (MonadThrow m, MonadState ST m) =>  m ()
checkExpectations = do
  m <- get
  let filtered = (Map.filter flFn m)
  if Map.null filtered  then pass else throwM $
    TestError $ "Test expectation was not met" ++ show (Map.assocs filtered)
  where
    flFn :: ExpectationStatus -> Bool
    flFn es = case exExpectCount es of
      Multiple ->  exOccurCount es == 0
      Once -> exOccurCount es /= 1
      Exact x -> exOccurCount es /= x

data TestError
  = TestError String
  | TZBTCError TzbtcClientError
  deriving Show

instance Exception TestError

-- Some constants
--
unsafeParsePublicKey :: Text -> PublicKey
unsafeParsePublicKey x = either (error . show) id $ parsePublicKey x

unsafeParseSecretKey :: Text -> SecretKey
unsafeParseSecretKey x = either (error . show) id $ parseSecretKey x

johnAddressRaw = "tz1dceuVQAueJyw3YXHZeRMe93XbeiCbGSes"
johnAddress = unsafeParseAddress johnAddressRaw
johnAddressPKRaw = "edpkuZjJ7wnk5Y4vCrXABmDBEd3fEEqX8yt71S3TnuyiCg5q4D4YGC"
johnAddressPK = unsafeParsePublicKey johnAddressPKRaw
johnSecretKeyRaw = "edsk3Dmh1qdoSwkpGWkKaLDFKBcTRdHaUsQ2otoFE7cVBzHBdgfx9d"
johnSecretKey = unsafeParseSecretKey johnSecretKeyRaw
johnAlias = "john"

bobAddressPKRaw = "edpkvGM6onCG3yi7YCgRgtHtF9ZqacjiAve3pKk6mNi1ftooG3A9wN"
bobAddressPK = unsafeParsePublicKey bobAddressPKRaw
bobSecretKeyRaw = "edsk3M7Z2qUrDDXGzb8Xw5KSYnv9WNgmaw1eLNv3x9rGRXNjFjjRZp"
bobSecretKey = unsafeParseSecretKey bobSecretKeyRaw

aliceAddressPKRaw = "edpkv8ey3XsdoYVVFEwBq7phjnUpdquYk5nCWj8CGZt1gAiivZYzV7"
aliceAddressPK = unsafeParsePublicKey aliceAddressPKRaw
aliceSecretKeyRaw = "edsk4XyAoKu2vXk7HweT3WjGoMwUeaeboN3kexdkNdfF4qMFb5sDwn"
aliceSecretKey = unsafeParseSecretKey aliceSecretKeyRaw

contractAddressRaw = "KT1HmhmNcZKmm2NsuyahdXAaHQwYfWfdrBxi" :: String
contractAddress = unsafeParseAddress $ toText contractAddressRaw

multiSigAddressRaw = "KT1MLCp7v3NiY9xeLe4XyPoS4AEgfXT7X5PX" :: String
multiSigAddress = unsafeParseAddress $ toText multiSigAddressRaw

operatorAddress1Raw = "tz1cLwfiFZWA4ZgDdxKiMgxACvGZbTJ2tiQQ" :: String
operatorAddress1 = unsafeParseAddress $ toText operatorAddress1Raw

configPath = "/home/user/.config/tzbtc/config.json"

configDir = "/home/user/.config/tzbtc"

multiSigFilePath = "/home/user/multisig_package"

sign_ :: SecretKey -> Text -> Signature
sign_ sk bs = case decodeHex (T.drop 2 bs) of
  Just dbs -> sign sk dbs
  Nothing -> error "Error with making signatures"

-- Test that no operations are called if the --dry-run flag
-- is provided in cmdline.
test_dryRunFlag :: TestTree
test_dryRunFlag = testGroup "Dry run does not execute any action"
  [ testCase "Handle values correctly with placeholders" $ do
      runMock (defaultHandlers $ defaultMockInput { miCmdLine = ["burn", "--value", "100", "--dry-run"] }) $ do
        addExpectation ParseCmdLine Once
        mainProgram
  ]

-- Test the setupClient command
-- Setup client with out any arguments should not overwrite the
-- existing config file
setupClientTestHandlers = (defaultHandlers (defaultMockInput { miCmdLine = ["setupClient"] }))
  { hPrintStringLn = \x ->
      let
          expectedMessage = "Not overwriting the existing config file at, \n\n" <> configPath <> "\n\nPlease remove the file and try again"
      in if x == expectedMessage
          then removeExpectation PrintsMessage
          else throwM $ TestError "Unexpected message"
  , hGetConfigPaths = do
      removeExpectation GetConfigPaths
      pure (DirPath configDir, configPath)
  , hDoesFileExist = \x -> if x == configPath then do
      removeExpectation ChecksFileExist
      pure True
      else throwM $ TestError "Unexpected file existence check"
  }

test_setupClient :: TestTree
test_setupClient = testGroup "`SetupClient` without arguments does not overwrite existing file"
  [ testCase "Check config file overwrite check" $
    let
      test = do
        addExpectation PrintsMessage Once
        addExpectation GetConfigPaths Once
        addExpectation ParseCmdLine Once
        addExpectation ChecksFileExist Once
        mainProgram
        checkExpectations
    in runMock setupClientTestHandlers test
  ]

-- TestSetup client with out any arguments creates a template file
setupClientWithoutArgsTestHandlers :: Handlers TestM
setupClientWithoutArgsTestHandlers = setupClientTestHandlers
  { hPrintStringLn = \_ -> removeExpectation PrintsMessage
  , hGetConfigPaths = do
      removeExpectation GetConfigPaths
      pure (DirPath configDir, configPath)
  , hWriteConfigPartial = \c ->
      if c == expectedConfig
      then removeExpectation WritesConfig
      else throwM $ TestError "Unexpected config file contents"
  , hCreateDirectoryIfMissing = \b x ->
      if unDirPath x ==  configDir && b
        then removeExpectation CreateDirectory
        else throwM $ TestError "Unexpected directiory creation request"
  , hDoesFileExist = \x -> if x == configPath
    then do
      removeExpectation ChecksFileExist
      pure False
    else throwM $ TestError $ "Unexpected file existence check"
  }
  where
    expectedConfig = ClientConfig
     { ccNodeAddress = Unavilable
     , ccNodePort = Unavilable
     , ccNodeUseHttps = Available False
     , ccContractAddress = Unavilable
     , ccMultisigAddress = Unavilable
     , ccUserAlias = Unavilable
     , ccTezosClientExecutable = Available "tezos-client"
     }

test_setupClientTemplate :: TestTree
test_setupClientTemplate = testGroup "SetupClient without arguments create file with placeholders"
  [ testCase "Check template file" $
    let
      test = do
        addExpectation ParseCmdLine Once
        addExpectation CreateDirectory Once
        addExpectation ChecksFileExist Once
        addExpectation WritesConfig Once
        addExpectation GetConfigPaths Once
        addExpectation PrintsMessage Once
        mainProgram
        checkExpectations
    in runMock setupClientWithoutArgsTestHandlers test
  ]

-- TestSetup client with required arguments creates a filled template file
setupClientTemplateFullTestHandlers :: Handlers TestM
setupClientTemplateFullTestHandlers =
  (defaultHandlers (defaultMockInput { miCmdLine =  args}))
    { hWriteConfigFull = \c ->
        if c == expectedConfig
        then removeExpectation WritesConfig
        else throwM $ TestError "Unexpected config file contents"
    , hCreateDirectoryIfMissing = \b x ->
        if unDirPath x ==  configDir && b then removeExpectation CreateDirectory
        else throwM $ TestError "Unexpected directiory creation request"
    , hDoesFileExist = \x -> if x == configPath
        then do
          removeExpectation ChecksFileExist
          pure False
        else throwM $ TestError $ "Unexpected file existence check"
    }
  where
    expectedConfig = ClientConfig
      { ccNodeAddress = "localhost"
      , ccNodePort = 2990
      , ccNodeUseHttps = False
      , ccContractAddress = Just contractAddress
      , ccMultisigAddress = Nothing
      , ccUserAlias = "bob"
      , ccTezosClientExecutable = "tezos-client"
      }
    args =
      [ "setupClient" , "--node-url", "localhost", "--node-port", "2990"
      , "--contract-address", contractAddressRaw
      , "--alias", "bob"
      ]

test_setupClientTemplateFull :: TestTree
test_setupClientTemplateFull = testGroup "SetupClient with arguments create file with placeholders"
  [ testCase "Check file template file" $
    let
      test = do
        addExpectation ParseCmdLine Once
        addExpectation PrintsMessage Once
        addExpectation GetConfigPaths Once
        addExpectation ChecksFileExist Once
        addExpectation CreateDirectory Once
        addExpectation WritesConfig Once
        mainProgram
        checkExpectations
    in runMock setupClientTemplateFullTestHandlers test
  ]

---- Test Creation of multisig package. Checks the following.
---- The command is parsed correctely
---- Checks the package is created with the provided parameter
---- The replay attack counter is correct
---- The multisig address is correct
---- The expected calls are made.
multiSigCreationTestHandlers :: Handlers TestM
multiSigCreationTestHandlers =
  (defaultHandlers (defaultMockInput { miCmdLine =  args}))
    { hReadConfig = case decode $ encode cc of
        Just x -> do
          removeExpectation ReadConfig
          pure $ Right x
        Nothing -> throwM $ TestError "Unexpected configuration decoding fail"
    , hRunTransactions = \_ _ -> throwM $ TestError "Unexpected `runTransactions` call"
    , hGetStorage = \x -> if x == toText multiSigAddressRaw
      then pure $ nicePackedValueToExpression (MS.mkStorage 14 3 [])
      else throwM $ TestError "Unexpected contract address"
    , hWriteFile = \fp bs -> do
      if fp == multiSigFilePath
      then do
        packageOk <- checkPackage bs
        if packageOk then removeExpectation WritesFile else throwM $ TestError "Package check failed"
      else throwM $ TestError "Unexpected multisig package file location"
    }
    where
      args =
        [ "addOperator"
        , "--operator", operatorAddress1Raw
        , "--multisig", multiSigFilePath
        ]
      cc :: ClientConfig
      cc = ClientConfig
        { ccNodeAddress = "localhost"
        , ccNodePort = 2990
        , ccNodeUseHttps = False
        , ccContractAddress = Just contractAddress
        , ccMultisigAddress = Just multiSigAddress
        , ccUserAlias = "bob"
        , ccTezosClientExecutable = "tezos-client"
        }
      checkToSign package = case getToSign package of
        Right (addr, (counter, _)) -> pure $
          ( addr == multiSigAddress &&
            counter == 14 )
        _ -> throwM $ TestError "Getting address and counter from package failed"
      checkPackage bs = case decodePackage bs of
        Right package -> case fetchSrcParam package of
          Right param -> do
            toSignOk <- checkToSign package
            pure $ toSignOk &&
              (param == (TZBTC.fromFlatParameter $ TZBTC.AddOperator
                (#operator .! operatorAddress1)))
          _ -> throwM $ TestError "Fetching parameter failed"
        _ -> throwM $ TestError "Decoding package failed"

test_createMultisigPackage :: TestTree
test_createMultisigPackage = testGroup "Create multisig package"
  [ testCase "Check package creation" $
    let
      test = do
        addExpectation ParseCmdLine Once
        addExpectation ReadConfig Once
        addExpectation WritesFile Once
        mainProgram
        checkExpectations
    in runMock multiSigCreationTestHandlers test
  ]

---- Test Signing of multisig package
---- Checks that the `signPackage` command correctly includes the
---- signature returned by the tezos-client.
multisigSigningTestHandlers :: Handlers TestM
multisigSigningTestHandlers =
  (defaultHandlers (defaultMockInput { miCmdLine =  args}))
    { hGetLineFromUser = do
        removeExpectation GetsLineFromUser
        pure "y"
    , hReadConfig = case decode $ encode cc of
        Just x -> do
          removeExpectation ReadConfig
          pure $ Right x
        Nothing -> throwM $ TestError "Unexpected configuration decoding fail"

    , hWriteFile = \fp bs -> do
        if fp == multiSigFilePath then do
          checkSignature_ bs
          removeExpectation WritesFile
        else throwM $ TestError "Unexpected file path to write"
    , hReadFile = \fp -> do
        if fp == multiSigFilePath then do
          removeExpectation ReadsFile
          pure $ encodePackage multisigSignPackageTestPackage
        else throwM $ TestError "Unexpected file read"
    , hGetAddressAndPKForAlias = \a -> if a == johnAlias
       then pure $ Right (johnAddress, johnAddressPK)
       else throwM $ TestError "Unexpected alias"
    , hSignWithTezosClient = \_ ->
       pure $ Right multisigSignPackageTestSignature
    }
    where
      args = [ "signPackage" , "--package", multiSigFilePath]
      cc :: ClientConfig
      cc = ClientConfig
        { ccNodeAddress = "localhost"
        , ccNodePort = 2990
        , ccNodeUseHttps = False
        , ccContractAddress = Just contractAddress
        , ccMultisigAddress = Just multiSigAddress
        , ccUserAlias = "john"
        , ccTezosClientExecutable = "tezos-client"
        }
      checkSignature_ bs = case decodePackage bs of
        Right package -> case pkSignatures package of
          ((pk, sig):_) -> if pk == johnAddressPK && sig == multisigSignPackageTestSignature
            then pass
            else throwM $ TestError "Bad signature found in package"
          _ -> throwM $ TestError "Unexpected package signatures"
        _ -> throwM $ TestError "Decoding package failed"

multisigSignPackageTestPackage :: Package
multisigSignPackageTestPackage = mkPackage
  multiSigAddress
  14
  contractAddress
  (TZBTCTypes.AddOperator (#operator .! operatorAddress1))

multisigSignPackageTestSignature :: Signature
multisigSignPackageTestSignature =
  sign_ johnSecretKey $ getBytesToSign multisigSignPackageTestPackage

test_multisigSignPackage :: TestTree
test_multisigSignPackage = testGroup "Sign multisig package"
  [ testCase "Check multisig signing" $
    let
      test = do
        addExpectation ParseCmdLine Once
        addExpectation ReadConfig Once
        addExpectation ReadsFile Once
        addExpectation PrintsMessage Multiple
        addExpectation GetsLineFromUser Once
        addExpectation WritesFile Once
        mainProgram
        checkExpectations
    in runMock multisigSigningTestHandlers  test
  ]

---- Test Execution of multisig package
---- Checks that the multisig contract parameter is created correctly
---- from the provided signed packages
multisigExecutionTestHandlers :: Handlers TestM
multisigExecutionTestHandlers =
  (defaultHandlers (defaultMockInput { miCmdLine =  args}))
    { hReadConfig = case decode $ encode cc of
        Just x -> do
          removeExpectation ReadConfig
          pure $ Right x
        Nothing -> throwM $ TestError "Unexpected configuration decoding fail"
    , hRunTransactions =  \addr params ->
        if addr == multiSigAddress then do
          case params of
            [] -> throwM $ TestError "Unexpected empty parameters"
            [Entrypoint "main" param] -> do
              case Typ.cast (toVal param) of
                Just param' -> case (fromVal param') of
                  (_ :: MS.ParamPayload, sigs) ->
                    if sigs ==
                      -- The order should be same as the one that we
                      -- return from getStorage mock
                      [ Just multisigExecutePackageTestSignatureAlice
                      , Just multisigExecutePackageTestSignatureBob
                      , Just multisigExecutePackageTestSignatureJohn
                      ] then removeExpectation RunsTransaction
                    else throwM $ TestError "Unexpected signature list"
                Nothing -> throwM $ TestError "Decoding parameter failed"
            [Entrypoint x _] -> throwM $ TestError $ "Unexpected entrypoint: " <> toString x
            [DefaultEntrypoint _] -> throwM $ TestError "Unexpected default entrypoint"
            _ -> throwM $ TestError "Unexpected multiple parameters"
        else throwM $ TestError "Unexpected multisig address"
    , hGetStorage = \x -> if x == toText multiSigAddressRaw
        then pure $ nicePackedValueToExpression (MS.mkStorage 14 3 [aliceAddressPK, bobAddressPK, johnAddressPK])
        else throwM $ TestError "Unexpected contract address"
    , hReadFile = \fp -> do
        case fp of
          "/home/user/multisig_package_bob" -> do
            removeExpectation ReadsFile
            encodePackage <$> addSignature_ multisigSignPackageTestPackage (bobAddressPK, multisigExecutePackageTestSignatureBob)
          "/home/user/multisig_package_alice" -> do
            removeExpectation ReadsFile
            encodePackage <$> addSignature_ multisigSignPackageTestPackage (aliceAddressPK, multisigExecutePackageTestSignatureAlice)
          "/home/user/multisig_package_john" -> do
            removeExpectation ReadsFile
            encodePackage <$> addSignature_ multisigSignPackageTestPackage (johnAddressPK, multisigExecutePackageTestSignatureJohn)
          _ -> throwM $ TestError "Unexpected file read"
    }
  where
    args =
      [ "callMultisig"
      , "--package", "/home/user/multisig_package_bob"
      , "--package", "/home/user/multisig_package_alice"
      , "--package", "/home/user/multisig_package_john"
      ]
    cc :: ClientConfig
    cc = ClientConfig
      { ccNodeAddress = "localhost"
      , ccNodePort = 2990
      , ccNodeUseHttps = False
      , ccContractAddress = Just contractAddress
      , ccMultisigAddress = Just multiSigAddress
      , ccUserAlias = "john"
      , ccTezosClientExecutable = "tezos-client"
      }
    addSignature_ package s = case addSignature package s of
      Right x -> pure x
      Left _ -> throwM $ TestError "There was an error signing the package"

multisigExecutePackageTestSignatureJohn :: Signature
multisigExecutePackageTestSignatureJohn =
  sign_ johnSecretKey $ getBytesToSign multisigSignPackageTestPackage

multisigExecutePackageTestSignatureBob :: Signature
multisigExecutePackageTestSignatureBob =
  sign_ bobSecretKey $ getBytesToSign multisigSignPackageTestPackage

multisigExecutePackageTestSignatureAlice :: Signature
multisigExecutePackageTestSignatureAlice =
  sign_ aliceSecretKey $ getBytesToSign multisigSignPackageTestPackage

test_multisigExecutePackage :: TestTree
test_multisigExecutePackage = testGroup "Sign multisig execution"
  [ testCase "Check multisig execution" $
    let
      test = do
        addExpectation ParseCmdLine Once
        addExpectation ReadConfig Once
        addExpectation ReadsFile (Exact 3)
        addExpectation RunsTransaction Once
        mainProgram
        checkExpectations
    in runMock multisigExecutionTestHandlers test
  ]
