// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Sort {
    function sort(
        uint256[] memory array,
        uint256[] memory index
    ) internal pure {
        _quickSort(_begin(array), _end(array), _begin(index), _end(index));
    }

    function lt(uint256 a, uint256 b) private pure returns (bool) {
        return a < b;
    }

    /**
     * @dev Pointer to the memory location of the first element of `array`.
     */
    function _begin(uint256[] memory array) private pure returns (uint256 ptr) {
        assembly ("memory-safe") {
            ptr := add(array, 0x20)
        }
    }

    /**
     * @dev Pointer to the memory location of the first memory word (32bytes) after `array`. This is the memory word
     * that comes just after the last element of the array.
     */
    function _end(uint256[] memory array) private pure returns (uint256 ptr) {
        unchecked {
            return _begin(array) + array.length * 0x20;
        }
    }

    /**
     * @dev Load memory word (as a uint256) at location `ptr`.
     */
    function _mload(uint256 ptr) private pure returns (uint256 value) {
        assembly {
            value := mload(ptr)
        }
    }

    /**
     * @dev Swaps the elements memory location `ptr1` and `ptr2`.
     */
    function _swap(uint256 ptr1, uint256 ptr2) private pure {
        assembly {
            let value1 := mload(ptr1)
            let value2 := mload(ptr2)
            mstore(ptr1, value2)
            mstore(ptr2, value1)
        }
    }

    // function sort(
    //     bytes
    // )

    function _quickSort(
        uint256 begin,
        uint256 end,
        uint256 beginIndex,
        uint256 endIndex
    ) private pure {
        unchecked {
            if (end - begin < 0x40) return;

            // Use first element as pivot
            uint256 pivot = _mload(begin);
            // Position where the pivot should be at the end of the loop
            uint256 pos = begin;
            uint256 posIndex = beginIndex;
            uint256 itIndex = beginIndex + 0x20;

            for (uint256 it = begin + 0x20; it < end; it += 0x20) {
                if (lt(_mload(it), pivot)) {
                    // If the value stored at the iterator's position comes before the pivot, we increment the
                    // position of the pivot and move the value there.
                    pos += 0x20;
                    posIndex += 0x20;
                    _swap(pos, it);
                    _swap(posIndex, itIndex);
                }
                itIndex += 0x20;
            }

            _swap(begin, pos); // Swap pivot into place
            _swap(beginIndex, posIndex); // Swap pivot into place
            _quickSort(begin, pos, beginIndex, posIndex); // Sort the left side of the pivot
            _quickSort(pos + 0x20, end, posIndex + 0x20, endIndex); // Sort the right side of the pivot
        }
    }
}
