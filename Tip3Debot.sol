pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

import "base/Debot.sol";
import "base/Terminal.sol";
import "base/AddressInput.sol";
import "base/AmountInput.sol";
import "base/Sdk.sol";
import "base/Menu.sol";
import "base/Upgradable.sol";
import "base/Transferable.sol";
import "base/ConfirmInput.sol";


interface IRootToken {
    struct rootTokenContractDetails {
        bytes name;
        bytes symbol;
        uint8 decimals;
        TvmCell wallet_code;
        uint256 root_public_key;
        address root_owner_address;
        uint128 total_supply;
    }

    function name() external returns (bytes);
    function symbol() external returns (bytes);
    function decimals() external returns (uint8);
    function total_supply() external returns (uint128);
    function getWalletAddress(uint256 wallet_public_key_, address owner_address_) external returns (address);
    function getDetails() external view returns (rootTokenContractDetails);
}

interface ITokenWallet {
    function balance() external returns (uint128);
    function transferToRecipient(
        uint256 recipient_public_key,
        address recipient_address,
        uint128 tokens,
        uint128 deploy_grams,
        uint128 transfer_grams,
        address send_gas_to,
        bool notify_receiver,
        TvmCell payload
    ) external;
}

interface IUserWallet {
    function submitTransaction(
        address dest,
        uint128 value,
        bool bounce,
        bool allBalance,
        TvmCell payload
    ) external returns (uint64 transId);
}

interface ITokenRegistry {
    function tokens() external returns (address[]);
}


contract Tip3Debot is Debot, Upgradable, Transferable {
    struct rootTokenContractDetails {
        bytes name;
        bytes symbol;
        uint8 decimals;
        TvmCell wallet_code;
        uint256 root_public_key;
        address root_owner_address;
        uint128 total_supply;
    }

    address public token_registry;

    address[] tokens_list;
    rootTokenContractDetails[] tokens_details;
    uint256 selected_token_id;

    // user data
    address wallet_address;
    address     token_wallet_address;
    uint128 token_wallet_balance;

    // user input
    string str_amount_to_send;
    uint128 amount_to_send;

    // receiver
    address receiver_wallet_address;

    constructor(string debotAbi, address _token_registry) public {
        setABI(debotAbi);
        token_registry = _token_registry;
    }

    function getVersion() public override returns (string name, uint24 semver) {
        (name, semver) = ("Broxus Tip3 token Debot", 1 << 16);
    }

    function start() public override {
        Terminal.print(0, "Hello, I'm Broxus TIP3 debot. I can help you transfer your TIP3 tokens.");
        AddressInput.get(tvm.functionId(getSenderWalletAddress), "Give me your wallet address to start");
    }

    function getSenderWalletAddress(address value) public {
        wallet_address = value;
        Terminal.print(0, "Thank you, now you can manage your tokens");
        showStartMenu();
    }

    function showStartMenu() public {
        Menu.select("Main menu", "", [
            MenuItem("Select TIP3 token", "", tvm.functionId(selectTip3Token))
        ]);
    }

    function backToMenu(uint32 index) public {
        showStartMenu();
    }


    function selectTip3Token(uint32 index) public {
        queryTokenRegistry();
	}

    function showTokensMenu() public {
        MenuItem[] items;

        for (uint i = 0; i < tokens_details.length; i++) {
            rootTokenContractDetails _details = tokens_details[i];
            items.push(MenuItem(_details.symbol, "", tvm.functionId(selectToken)));
        }

        items.push(MenuItem("Back", "", tvm.functionId(backToMenu)));

        Menu.select("Token menu", "Select token from list below:", items);
    }

    function selectToken(uint32 index) public {
        selected_token_id = index;
        rootTokenContractDetails _details = tokens_details[index];

        string str = format(
            "Token info:\n\nName - {}\nDecimals - {}\nTotal supply - {}\nRoot address - {}",
            _details.name,
            _details.decimals,
            _details.total_supply,
            tokens_list[selected_token_id]
        );
        Terminal.print(0, str);

        queryTokenWalletAddress();
    }

    // called from queryTokenWalletBalance callback
    function getAmountToSend() public {
//        AmountInput.get(tvm.functionId(show), "Enter input value",  tokens_details[selected_token_id].decimals, 0,  tokens_details[selected_token_id].total_supply);

        Terminal.input(tvm.functionId(getInputAmount), "Enter amount you want to send. Example: 123 or 123.11", false);
    }

    function show(uint128 value) public {
        Terminal.print(0, format("Val - {}", value));
    }

    function getInputAmount(string value) public {
        bool status; uint8 decimals = tokens_details[selected_token_id].decimals;
        (amount_to_send, status) = fromFractional(value, decimals);

        if (status == false) {
            Terminal.input(tvm.functionId(getInputAmount), "Wrong input, please, try again", false);
            return;
        }

        str_amount_to_send = value;

        string str = format(
            "You entered {}, which is {} according to token decimals ({})",
            value, amount_to_send, decimals
        );
        Terminal.print(0, str);

        if (amount_to_send > token_wallet_balance) {
            Terminal.input(
                tvm.functionId(getInputAmount),
                format("Amount exceeds your balance ({}), please, enter less value", toFractional(token_wallet_balance, decimals)),
                false
            );
        } else {
            getReceiverAddress();
        }
    }

    function getReceiverAddress() public {
        AddressInput.get(tvm.functionId(checkWalletAddressReceiver), "Now enter receiver wallet address");
    }

    function checkWalletAddressReceiver(address value) public {
        receiver_wallet_address = value;
        finalize();
    }

    function finalize() public {
        string token_symbol = tokens_details[selected_token_id].symbol;
        string final_msg = format(
            "You want to transfer {} ({}) {} tokens to {}",
            str_amount_to_send, amount_to_send, token_symbol, receiver_wallet_address
        );
        Terminal.print(0, final_msg);
        ConfirmInput.get(tvm.functionId(submit), "Submit transaction?");
    }

    function submit(bool value) public {
        if (!value) {
            Terminal.print(0, "Ok, let's do anything else");
            showStartMenu();
            return;
        }

        optional(uint256) pubkey = 0;

        TvmBuilder builder;
        TvmCell body = tvm.encodeBody(
            ITokenWallet.transferToRecipient,
            0,
            receiver_wallet_address,
            amount_to_send,
            uint128(50000000),
            uint128(0),
            wallet_address,
            false,
            builder.toCell()
        );

        IUserWallet(wallet_address).submitTransaction{
                abiVer: 2,
                extMsg: true,
                sign: true,
                pubkey: pubkey,
                time: uint64(now),
                expire: 0,
                callbackId: tvm.functionId(success),
                onErrorId: tvm.functionId(onSendFailed)
        }(token_wallet_address, uint128(500000000), true, false, body);

    }

    // --------------------------- QUERY FUNCTIONS -------------------------------------
    function queryTokenRegistry() public view {
        optional(uint256) pubkey;
        ITokenRegistry(token_registry).tokens{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setTokens),
            onErrorId: 0
        }();
    }

    function queryTokenDetails(uint256 token_id) public {
        address token_addr = tokens_list[token_id];

        optional(uint256) pubkey;
        IRootToken(token_addr).getDetails{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setTokenDetails),
            onErrorId: 0
        }();
    }

    function queryTokenWalletAddress() public view {
        optional(uint256) pubkey;
        IRootToken(tokens_list[selected_token_id]).getWalletAddress{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setTokenWalletAddress),
            onErrorId: 0
        }(0, wallet_address);
    }

    function queryTokenWalletBalance() public view {
        optional(uint256) pubkey;
        ITokenWallet(token_wallet_address).balance{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setTokenWalletBalance),
            onErrorId: 0
        }();
    }


    // ---------------------------- CALLBACKS ---------------------------------
    function setTokens(address[] _tokens) public {
        tokens_list = _tokens;
        delete tokens_details;

        for (uint i = 0; i < tokens_list.length; i++) {
            queryTokenDetails(i);
        }
        Terminal.print(tvm.functionId(showTokensMenu), "");
    }

    function setTokenDetails(rootTokenContractDetails _token_details) public {
        tokens_details.push(_token_details);
    }

    function setTokenWalletAddress(address _token_wallet_address) public {
        token_wallet_address = _token_wallet_address;

        Sdk.getAccountType(tvm.functionId(checkTokenWalletDeployed), token_wallet_address);
    }

    function checkTokenWalletDeployed(int8 acc_type) public {
        if ((acc_type==-1)||(acc_type==0)) {
            string symbol = tokens_details[selected_token_id].symbol;
            Terminal.print(0, format("You don't have any {}, use another token", symbol));
            showTokensMenu();
        } else {
            queryTokenWalletBalance();
        }
    }

    function setTokenWalletBalance(uint128 _balance) public {
        token_wallet_balance = _balance;

        string token_symbol = tokens_details[selected_token_id].symbol;
        string balance_str = toFractional(_balance, tokens_details[selected_token_id].decimals);

//        Terminal.print(0, format("Your token wallet address - {}", token_wallet_address));
        Terminal.print(0, format("Your balance - {} {}", balance_str, token_symbol));

        getAmountToSend();
    }

    function success(uint64 res) public {
        Terminal.print(tvm.functionId(showStartMenu), "Your tokens are successfully transfered!");
    }

    // ------------------------------ ERR HANDLERS --------------------------------
    function onSendFailed(uint32 sdkError, uint32 exitCode) public {
        Terminal.print(0, format("Send failed. Sdk error = {}, Error code = {}", sdkError, exitCode));
        ConfirmInput.get(tvm.functionId(submit), "Do you want to retry?");
    }

    // ------------------------------ UPGRADABLE ----------------------------------
    function onCodeUpgrade() internal override {}

    // ------------------------------ UTILS ---------------------------------------
    function toFractional(uint128 balance, uint8 decimals) internal view returns (string) {
        uint left_part = balance / uint256(10) ** decimals;
        uint right_part = balance % uint256(10) ** decimals;
        return format("{}.{}", left_part, right_part);
    }

    function fromFractional(string value, uint8 decimals) internal returns (uint128, bool) {
        uint8 sep_id = findSeparator(value, ".");

        uint256 result; bool status;
        if (sep_id == 0) {
            // no separator found, integer given
            (result, status) = stoi(value);
            if ((status == false) || (result == 0)) {
                return (0, false);
            }
            // add decimals
            result = result * uint256(10) ** uint256(decimals);
        } else {
            // found separator, add decimals to real and int parts and sum them
            string str_real_part = value.substr(sep_id + 1, value.byteLength() - (sep_id + 1));
            string str_int_part = value.substr(0, sep_id);

            // sanity checks
            (uint256 int_part, bool st1) = stoi(str_int_part);
            (uint256 real_part, bool st2) = stoi(str_real_part);

            if ((st1 == false) || (st2 == false) || ((int_part + real_part) == 0)) {
                return (0, false);
            }
            // convert real part
            uint256 real_part_with_decimals = parseRealPart(str_real_part);

            result = int_part * uint256(10) ** uint256(decimals) + real_part_with_decimals;
        }
        return (uint128(result), true);
    }

    function findSeparator(string str_num, string sep) internal view returns (uint8 sep_id) {
        for (uint8 i = 0; i < str_num.byteLength(); i++) {
            if (str_num.substr(i, 1) == sep) {
                sep_id = i;
            }
        }
    }

    function parseRealPart(string real_part) internal view returns (uint256) {
        // lets day we got 1.0012 in token with 6 decimals, so that
        // real_part -> 0012
        // decimals  -> 6
        uint8 decimals = tokens_details[selected_token_id].decimals;
        uint8 power = uint8(decimals) - real_part.byteLength();
        (uint256 result, bool st) = stoi(real_part);
        // result = 12 * 10**2
        return result * uint256(10) ** uint256(power);
    }
}
