// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library DigitExtractor {
    function extractFirst14Digits(uint256 randomNumber) internal pure returns (uint256) {
        string memory numberStr = uintToString(randomNumber);
        string memory first14DigitsStr = substring(numberStr, 0, 14);
        return stringToUint(first14DigitsStr);
    }

    function uintToString(uint256 v) internal pure returns (string memory) {
        if (v == 0) {
            return "0";
        }
        uint256 maxLength = 80;
        bytes memory reversed = new bytes(maxLength);
        uint256 i = 0;
        while (v != 0) {
            uint8 remainder = uint8(v % 10);
            v = v / 10;
            reversed[i++] = bytes1(remainder + 48);
        }
        bytes memory s = new bytes(i);
        for (uint256 j = 0; j < i; j++) {
            s[j] = reversed[i - j - 1];
        }
        return string(s);
    }

    function stringToUint(string memory s) internal pure returns (uint256) {
        bytes memory b = bytes(s);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            if (uint8(b[i]) >= 48 && uint8(b[i]) <= 57) {
                result = result * 10 + (uint256(uint8(b[i])) - 48);
            }
        }
        return result;
    }

    function substring(string memory str, uint256 startIndex, uint256 endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }
}
