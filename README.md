
```markdown
# ProductionERC20

[![Solidity](https://img.shields.io/badge/Solidity-^0.8.24-blue)](https://soliditylang.org/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-5.x-4E5EE4)](https://openzeppelin.com/contracts/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

`ProductionERC20` — это расширенный ERC20-токен для production-использования, построенный на OpenZeppelin Contracts 5.x. Контракт сочетает неизменяемый cap, сжигание, паузу, permit, чёрный список, опциональную комиссию с перевода и линейный вестинг.

> **Важно:** проект ДОЛЖЕН использовать зафиксированную (pinned) и аудированную версию OpenZeppelin Contracts 5.x. Не используйте плавающие версии зависимостей в production.

---

## Возможности

- **ERC20** — стандартный токен с `name`, `symbol`, `decimals`.
- **ERC20Capped** — неизменяемый максимальный объём эмиссии (`maxSupply`).
- **ERC20Burnable** — держатели могут сжигать свои токены.
- **ERC20Pausable** — владелец может приостановить все переводы.
- **ERC20Permit** — gasless-одобрения через подпись (EIP-2612).
- **Ownable2Step** — безопасная передача владения в два шага.
- **Чёрный список** — владелец может блокировать адреса.
- **Комиссия с перевода** — до 20% (2000 bps). 25% комиссии уходит владельцу, 75% — на контракт.
- **Линейный вестинг** — владелец создаёт вестинги для бенефициаров; токены резервируются на контракте.
- **Rescue ERC20** — владелец может спасти чужие ERC20, случайно отправленные на контракт.
- **Кастомные ошибки и события** — экономия газа и удобная отладка.
- **Отключение комиссии при renounceOwnership** — после отказа от владения комиссия навсегда становится 0.

---

## Наследование

```solidity
contract ProductionERC20 is
    ERC20,
    ERC20Capped,
    ERC20Burnable,
    ERC20Pausable,
    ERC20Permit,
    Ownable2Step
```

---

Ключевые параметры

Параметр Описание
MAX_FEE_BPS Максимальная комиссия: 2000 (20.00%)
BPS_DENOMINATOR 10_000
OWNER_FEE_BPS Доля владельца от комиссии: 2500 (25%)
maxSupply Неизменяемый максимальный объём эмиссии
feeBps Текущая комиссия в bps
blacklist Маппинг заблокированных адресов
vestingSchedules Маппинг вестингов по бенефициарам
totalReserved Сумма токенов, зарезервированных под вестинги

---

Основные функции

Управление эмиссией

· mint(address to, uint256 amount) — только владелец. Нельзя минтить на address(0), в чёрный список или на 0.
· decimals() — возвращает заданные при деплое decimals.

Комиссия

· setFeeBps(uint256 newFeeBps) — только владелец. Максимум MAX_FEE_BPS.
· renounceOwnership() — отключает комиссию (feeBps = 0) и отказывается от владения.

Чёрный список и пауза

· setBlacklist(address account, bool value) — только владелец. Нельзя добавить владельца или address(0).
· pause() / unpause() — только владелец.

Комиссии контракта

· withdrawContractFees(address to, uint256 amount) — только владелец. Можно вывести только свободный баланс, не зарезервированный под вестинги.

Вестинг

· createVesting(address beneficiary, uint256 totalAmount, uint256 start, uint256 cliff, uint256 duration) — только владелец.
· releaseVestedTokens() — вызывается бенефициаром. Переводит доступную сумму.
· vestedAmount(address beneficiary) — сколько токенов уже заработано.
· releasableAmount(address beneficiary) — сколько можно получить прямо сейчас.

Rescue

· rescueTokens(IERC20 token, address to, uint256 amount) — только владелец. Нельзя спасти сам ProductionERC20.

---

События

· FeeBpsUpdated(uint256 indexed oldFeeBps, uint256 indexed newFeeBps)
· BlacklistUpdated(address indexed account, bool blacklisted)
· VestingCreated(address indexed beneficiary, uint256 totalAmount, uint256 start, uint256 cliff, uint256 duration)
· TokensReleased(address indexed beneficiary, uint256 amount)
· ContractFeesWithdrawn(address indexed to, uint256 amount)
· ERC20Rescued(address indexed token, address indexed to, uint256 amount)

---

Ошибки

· ZeroAddress()
· InvalidCap()
· InvalidFee()
· BlacklistedAddress(address account)
· AmountZero()
· InsufficientFreeBalance()
· InvalidVesting()
· VestingAlreadyExists()
· NoVesting()
· NothingToRelease()
· ReservedBalanceViolation()
· CannotRescueSelf()
· AmountTooLarge()
· CannotBlacklistOwner()

---

Установка и зависимости

```bash
npm install @openzeppelin/contracts@5.x
# или
forge install OpenZeppelin/openzeppelin-contracts@v5.x
```

Убедитесь, что версия OpenZeppelin зафиксирована в package.json / foundry.toml / remappings.txt.

---

Компиляция

Hardhat

```bash
npx hardhat compile
```

Foundry

```bash
forge build
```

---

Деплой

Конструктор:

```solidity
constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_,
    uint256 cap_,
    address initialOwner_
)
```

Пример с Foundry:

```solidity
ProductionERC20 token = new ProductionERC20(
    "MyToken",
    "MTK",
    18,
    1_000_000e18,
    owner
);
```

Параметры:

· name_ — имя токена.
· symbol_ — символ.
· decimals_ — количество знаков после запятой.
· cap_ — максимальная эмиссия. Должна быть > 0.
· initialOwner_ — адрес владельца. Не может быть address(0).

---

Пример использования

Установка комиссии

```solidity
token.setFeeBps(500); // 5%
```

Создание вестинга

```solidity
token.createVesting(
    beneficiary,
    100_000e18,          // всего токенов
    block.timestamp,     // start
    30 days,             // cliff
    365 days             // duration
);
```

Получение вестинга

```solidity
token.releaseVestedTokens(); // вызывается бенефициаром
```

Вывод комиссий

```solidity
token.withdrawContractFees(treasury, amount);
```

---

Безопасность и централизация

Контракт предполагает высокий уровень доверия к владельцу. Владелец может:

· минтить новые токены в пределах cap;
· ставить и снимать паузу;
· добавлять и убирать адреса из чёрного списка;
· устанавливать комиссию до 20%;
· создавать вестинги;
· выводить свободные комиссии;
· спасать чужие ERC20.

Для production рекомендуется:

· использовать мультисиг или таймлок в качестве владельца;
· зафиксировать аудированную версию OpenZeppelin Contracts 5.x;
· провести независимый аудит;
· покрыть тестами все ветки: комиссии, чёрный список, паузу, cap, вестинги, rescue;
· проверить, что initialOwner_ не является контрактом, который не может вызывать функции.

Известные особенности

· При renounceOwnership() комиссия обнуляется, но событие FeeBpsUpdated может показать старое значение 0 вместо предыдущего. Это не влияет на безопасность, но стоит учитывать при индексации событий.
· Владелец не может быть добавлен в чёрный список, но может передать владение уже заблокированному адресу. Такой владелец не сможет разблокировать себя, пока не передаст владение дальше.
· Если добавить address(this) в чёрный список, функции withdrawContractFees и releaseVestedTokens перестанут работать. Это DoS со стороны владельца, но владелец и так имеет широкие полномочия.

---

Тестирование

Рекомендуемые сценарии:

1. Деплой с корректными и некорректными параметрами.
2. mint с учётом cap, чёрного списка и нулевого адреса.
3. Переводы с комиссией и без.
4. Распределение комиссии: владелец + контракт.
5. setFeeBps в пределах и вне лимита.
6. setBlacklist и переводы с/на заблокированные адреса.
7. pause / unpause.
8. Создание вестинга, расчёт vestedAmount, releasableAmount, releaseVestedTokens.
9. Вывод комиссий с учётом totalReserved.
10. rescueTokens для сторонних ERC20 и запрет на rescue самого себя.
11. renounceOwnership и обнуление комиссии.
12. Проверка событий и кастомных ошибок.

---

Лицензия

licence

```
