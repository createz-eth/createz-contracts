// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IProfile} from "./IProfile.sol";

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {IERC721Metadata} from "openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

// metadata https://docs.opensea.io/docs/metadata-standards
// TODO add ERC 4906 metadata events
// TODO change token id generation
// TODO add burn
// TODO add gap?
// TODO fix supportsInterface
// TODO add meta information, name, links, etc
// TODO max supply?
// TODO bind to another ERC721 for identity verification
contract Profile is IProfile, ERC721EnumerableUpgradeable {
    using Strings for uint256;

    struct ProfileData {
        string name;
        string description;
        string image;
        string externalUrl;
    }

    uint256 private nextTokenId;
    mapping(uint256 => ProfileData) private profileData;

    constructor() {
        // disable direct usage of implementation contract
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC721_init("CreateZ Profile", "crzP");
        nextTokenId = 1;
    }

    function mint(
        string memory _name,
        string memory _description,
        string memory _image,
        string memory _externalUrl
    ) external returns (uint256) {
        require(bytes(_name).length > 2, "crzP: name too short");
        uint256 tokenId = nextTokenId++;

        profileData[tokenId] = ProfileData(
            _name,
            _description,
            _image,
            _externalUrl
        );
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
        require(_ownerOf(tokenId) != address(0), "crzP: Token does not exist");

        string memory output = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name":"',
                        profileData[tokenId].name,
                        '","description":"',
                        profileData[tokenId].description,
                        '","image":"',
                        profileData[tokenId].image,
                        '","external_url":"',
                        profileData[tokenId].externalUrl,
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
                    '{"name": "CreateZ Profile", "description": "CreateZ Profiles hold multiple Subscription Contracts that allow users to publicly support a given Creator", "image": "https://createz.eth/profile.png", "external_link": "https://createz.eth" }'
                )
            )
        );
        return string.concat("data:application/json;base64,", json);
    }
}