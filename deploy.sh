debot_abi=$(cat tmp/Tip3Debot.abi.json | xxd -ps -c 20000)
tonos-cli deploy --abi tmp/Tip3Debot.abi.json --sign keyfile.json tmp/Tip3Debot.tvc "{\"debotAbi\":\"$debot_abi\", \"_token_registry\": \"0:5b08710f31ac1275fa2971c31af9e55dfa37e234c24579a3614a2991d13fa2ad\"}"

