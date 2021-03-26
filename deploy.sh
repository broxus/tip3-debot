debot_abi=$(cat build/Tip3Debot.abi.json | xxd -ps -c 20000)
tonos-cli deploy --abi build/Tip3Debot.abi.json --sign keyfile.json build/Tip3Debot.tvc "{\"debotAbi\":\"$debot_abi\", \"_token_registry\": \"0:b9cafa7e84bcee673091e51c970da5f11f930fa067e950678e11bce727be2439\"}"

