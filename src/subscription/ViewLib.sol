// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscriptionInternal} from "./ISubscription.sol";

import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

library ViewLib {
    // TODO add symbol to contractURI

    using Strings for uint256;
    using Strings for address;

    function contractData(ISubscriptionInternal s) internal view returns (string memory) {
        string memory output;
        {
            (address token, uint256 rate, uint256 lock, uint256 epochSize, uint256 maxSupply) = s.settings();
            output = string(
                abi.encodePacked(
                    '{"trait_type":"token","value":"',
                    token.toHexString(),
                    '"},{"trait_type":"rate","value":"',
                    rate.toString(),
                    '"},{"trait_type":"lock","value":',
                    lock.toString(),
                    '},{"trait_type":"epoch_size","value":',
                    epochSize.toString(),
                    '},{"trait_type":"max_supply","value":"',
                    maxSupply.toString(),
                    '"}'
                )
            );
        }

        {
            (uint256 currentEpoch, uint256 lastProcessedEpoch) = s.epochState();
            output = string(
                abi.encodePacked(
                    output,
                    ',{"trait_type":"owner","value":"',
                    s.owner().toHexString(),
                    '"},{"trait_type":"current_epoch","value":"',
                    currentEpoch.toString(),
                    '"},{"trait_type":"last_processed_epoch","value":"',
                    lastProcessedEpoch.toString(),
                    '"}'
                )
            );
        }
        {
            output = string(
                abi.encodePacked(
                    output,
                    ',{"trait_type":"claimable","value":"',
                    s.claimable().toString(),
                    '"},{"trait_type":"deposits_claimed","value":"',
                    s.claimed().toString(),
                    '"},{"trait_type":"tips_claimed","value":"',
                    s.claimedTips().toString(),
                    '"},{"trait_type":"total_supply","value":"',
                    s.totalSupply().toString(),
                    '"},{"trait_type":"active_shares","value":"',
                    s.activeSubShares().toString(),
                    '"},{"trait_type":"flags","value":"',
                    s.getFlags().toString(),
                    '"}'
                )
            );
        }

        (string memory description, string memory image, string memory externalUrl) = s.metadata();
        output = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name":"',
                        s.name(),
                        '","description":"',
                        description,
                        '","image":"',
                        image,
                        '","external_url":"',
                        externalUrl,
                        '","attributes":[',
                        output,
                        "]}"
                    )
                )
            )
        );

        output = string(abi.encodePacked("data:application/json;base64,", output));

        return output;
    }

    function tokenData(ISubscriptionInternal s, uint256 tokenId) internal view returns (string memory) {
        // TODO mind changes to contract-wide metadata need to fire ERC4906 events
        string memory output;

        {
            output = string(
                abi.encodePacked(
                    '{"trait_type":"deposited","value":"',
                    s.deposited(tokenId).toString(),
                    '"},{"trait_type":"spent","value":"',
                    s.spent(tokenId).toString(),
                    '"},{"trait_type":"unspent","value":"',
                    s.unspent(tokenId).toString(),
                    '"},{"trait_type":"withdrawable","value":"',
                    s.withdrawable(tokenId).toString(),
                    '"},{"trait_type":"tips","value":"',
                    s.tips(tokenId).toString(),
                    '"}'
                )
            );
        }

        {
            output = string(
                abi.encodePacked(
                    output,
                    ',{"trait_type":"is_active","value":',
                    s.isActive(tokenId) ? "true" : "false",
                    '},{"trait_type":"multiplier","value":',
                    uint256(s.multiplier(tokenId)).toString(),
                    '},{"trait_type":"expires_at","value":"',
                    s.expiresAt(tokenId).toString(),
                    '"}'
                )
            );
        }

        output = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name":"',
                        s.symbol(),
                        " #",
                        tokenId.toString(),
                        '","description":"',
                        "A subscription of ",
                        s.name(),
                        '","image":"',
                        "",
                        '","external_url":"',
                        '","attributes":[',
                        output,
                        "]}"
                    )
                )
            )
        );

        return string.concat("data:application/json;base64,", output);
    }
}
