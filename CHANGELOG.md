# Changelog

## [Unreleased] - 2026-01-06

### 새로운 기능 (New Features)

#### 1. BLS 서명 지원 (`CommitReveal2BLS`)
- **파일**: [src/CommitReveal2BLS.sol](src/CommitReveal2BLS.sol)
- **설명**: BLS(Boneh-Lynn-Shacham) 서명을 사용한 새로운 CommitReveal2 구현
- **주요 기능**:
  - BLS 서명 검증을 통한 가스 효율적인 집계 서명
  - 운영자별 BLS 공개키 매핑 (`s_operatorBLSPubKeys`)
  - `depositAndActivate(BLS.G1Point memory pubKey)` 함수로 BLS 공개키와 함께 활성화
  - `generateRandomNumber`에서 BLS pairing 검증 사용

#### 2. 리더 선출 메커니즘 (`LeaderSelection` + `CommitReveal2WithLeaderSelection`)
- **파일**: 
  - [src/LeaderSelection.sol](src/LeaderSelection.sol) (신규)
  - [src/CommitReveal2WithLeaderSelection.sol](src/CommitReveal2WithLeaderSelection.sol) (신규)
- **설명**: 커밋-공개 방식의 탈중앙화된 리더 선출 메커니즘
- **주요 기능**:
  - `commit(uint256 cv)`: 커밋 단계에서 해시값 제출
  - `reveal(uint256 revealValue)`: 공개 단계에서 원본값 공개
  - `resume()`: 공개된 값들의 해시를 기반으로 새 리더 선출
  - 커밋/공개하지 않은 운영자 자동 비활성화 및 슬래시 처리
- **상태 변수**:
  - `s_cvsForLeaderSelection`: 커밋 값 저장
  - `s_revealForLeaderSelection`: 공개 값 저장
  - `s_commitDurationForLeaderSelection`: 커밋 기간 (기본 60초)
  - `s_revealDurationForLeaderSelection`: 공개 기간 (기본 60초)

#### 3. BLS 라이브러리
- **파일**: [src/libraries/BLS.sol](src/libraries/BLS.sol) (신규)
- **설명**: BLS12-381 곡선 연산을 위한 라이브러리 (Solady 기반)
- **주요 기능**:
  - G1/G2 포인트 연산 (add, msm)
  - Pairing 검증
  - Fp/Fp2 → G1/G2 매핑
  - `hashToG2` 함수

---

### 테스트 추가 (Test Additions)

#### 1. BLS 가스 테스트
- **파일**: [test/gas/CommitReveal2Gas.t.sol](test/gas/CommitReveal2Gas.t.sol)
- **변경 사항**:
  - `CommitReveal2BLS` import 추가
  - `BLS` 라이브러리 import 추가
  - `_deployBLSContracts()` 헬퍼 함수 추가
  - `test_commitReveal2BLSGas()` 테스트 함수 추가
  - BLS G1/G2 곱셈 헬퍼 함수 (`_blsg1mul`, `_blsg2mul`)
  - `G1_GENERATOR()` 상수 함수

#### 2. 리더 선출 가스 테스트
- **파일**: [test/gas/ForManuscriptGas.t.sol](test/gas/ForManuscriptGas.t.sol)
- **변경 사항**:
  - `CommitReveal2WithLeaderSelection` import 추가
  - 새로운 상태 변수: `s_leaderWithholdingWithLeaderSelectionGas`, `s_commitGas`, `s_revealGas`
  - `test_LeaderWithholdingWithLeaderSelectionGas()` 테스트 함수 추가
    - 경로: `submitMerkleRoot() → failToRequestSOrGenerateRandomNumber() → commit() → reveal() → resume() → submitMerkleRoot() → generateRandomNumber()`
  - `_deployContractsWithLeaderSelection()` 헬퍼 함수
  - `_predictNewLeader()` 헬퍼 함수
  - `_setSCoCvRevealOrdersWithLeaderSelection()` 헬퍼 함수

#### 3. 테스트 헬퍼 업데이트
- **파일**: [test/shared/CommitReveal2Helper.sol](test/shared/CommitReveal2Helper.sol)
- **변경 사항**:
  - `CommitReveal2BLS` import 추가
  - `_setSCoCvRevealOrdersBLS()` 함수 추가 (BLS 컨트랙트용)

---

### 가스 비교 리포트 (Gas Comparison Reports)

#### 리더 보류 시나리오 비교
- **파일**: 
  - [output/LeaderWithholding_GasComparison_Report.md](output/LeaderWithholding_GasComparison_Report.md)
- **내용**: 기존 방식 vs 리더 선출 방식 가스 비용 비교
  - 32 운영자 기준: 602,138 gas → 2,092,589 gas (+247.5% 오버헤드)
  - 주요 오버헤드: 커밋 (~25,696 gas/운영자) + 공개 (~25,566 gas/운영자)

---

### 요약 (Summary)

| 카테고리 | 파일 수 | 설명 |
|---------|--------|------|
| 신규 컨트랙트 | 3 | `CommitReveal2BLS`, `LeaderSelection`, `CommitReveal2WithLeaderSelection` |
| 신규 라이브러리 | 1 | `BLS.sol` |
| 테스트 수정 | 3 | `CommitReveal2Gas.t.sol`, `ForManuscriptGas.t.sol`, `CommitReveal2Helper.sol` |
| 리포트 | 1 | 가스 비교 분석 리포트 |