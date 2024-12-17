// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IProfile} from "./IProfile.sol";

import {TokenIdProvider} from "../TokenIdProvider.sol";

import {OzERC721Enumerable, OzERC721EnumerableBind} from "../dependency/OzERC721Enumerable.sol";
import {OzInitializable, OzInitializableBind} from "../dependency/OzInitializable.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IERC721Metadata} from "openzeppelin-contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

// metadata https://docs.opensea.io/docs/metadata-standards
// TODO add ERC 4906 metadata events
// TODO change token id generation
// TODO add burn
// TODO fix supportsInterface
// TODO add meta information, name, links, etc
// TODO max supply?
// TODO bind to another ERC721 for identity verification
contract Profile is
    IProfile,
    UUPSUpgradeable,
    TokenIdProvider,
    OwnableUpgradeable,
    OzInitializableBind,
    OzERC721EnumerableBind
{
    using Strings for uint256;

    struct ProfileData {
        string name;
        string description;
        string image;
        string externalUrl;
    }

    struct ProfileStorage {
        mapping(uint256 => ProfileData) profileData;
    }

    // keccak256(abi.encode(uint256(keccak256("subsub.storage.profile.Profile")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ProfileStorageLocation = 0xa357ab46154347e62334c40b540d88802eb0c18fc231ff964526879cc3e0b200;

    function _getProfileStorage() private pure returns (ProfileStorage storage $) {
        assembly {
            $.slot := ProfileStorageLocation
        }
    }

    constructor() {
        // disable direct usage of implementation contract
        _disableInitializers();
    }

    function initialize(address owner) public initializer {
        __ERC721_init("SubSub Profile", "subP");
        __TokenIdProvider_init_unchained(0);
        __Ownable_init_unchained(owner);
    }

    function _authorizeUpgrade(address) internal virtual override {
        _checkOwner();
    }

    function mint(string memory _name, string memory _description, string memory _image, string memory _externalUrl)
        external
        returns (uint256)
    {
        require(bytes(_name).length > 2, "subP: name too short");
        uint256 tokenId = _nextTokenId();

        ProfileStorage storage $ = _getProfileStorage();
        $.profileData[tokenId] = ProfileData(_name, _description, _image, _externalUrl);
        _safeMint(_msgSender(), tokenId);

        emit Minted(_msgSender(), tokenId);

        return tokenId;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721Upgradeable, IERC721Metadata)
        returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "subP: Token does not exist");

        ProfileStorage storage $ = _getProfileStorage();
        string memory output = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name":"',
                        $.profileData[tokenId].name,
                        '","description":"',
                        $.profileData[tokenId].description,
                        '","image":"',
                        $.profileData[tokenId].image,
                        '","external_url":"',
                        $.profileData[tokenId].externalUrl,
                        '"',
                        "}"
                    )
                )
            )
        );

        return string.concat("data:application/json;base64,", output);
    }

    function contractURI() external pure returns (string memory) {
        string memory json = Base64.encode(
            bytes(
                string(
                    '{"name": "SubSub Profile", "description": "SubSub Profiles hold multiple Subscription Contracts that allow users to publicly support a given Creator", "image": "https://subsub.eth/profile.png", "external_link": "https://subsub.eth" }'
                )
            )
        );
        return string.concat("data:application/json;base64,", json);
    }
}
