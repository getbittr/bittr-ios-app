package com.bittr.android.core.network

import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

/**
 * One bittr order: the customer's IBAN and email, and the partner details and deposit code the
 * backend assigned — iOS's `IbanEntity` (`Buy/IbanEntity.swift`), field for field.
 *
 * Immutable here where iOS mutates a class in place; the store's [BittrCustomerStore.update] is
 * where a change is made, so every change is also a write.
 */
data class IbanEntity(
    val id: String,
    val order: Int = 0,
    val yourIbanNumber: String = "",
    val yourEmail: String = "",
    val ourIbanNumber: String = "",
    val ourName: String = DEFAULT_PARTNER_NAME,
    /** The deposit code. Empty until `POST /customer` succeeds. */
    val yourUniqueCode: String = "",
    val emailToken: String = "",
    val ourSwift: String = "",
    val lightningAddressUsername: String = "",
    /** `""` until the backend reports one, then `"lightning"` or `"onchain"`. */
    val paymentMode: String = "",
    /** Published T&C §2.5 confirmation, ISO-8601 UTC. Null when never collected. */
    val initiativeConfirmedAt: String? = null,
) {
    val hasDepositCode: Boolean get() = yourUniqueCode.isNotEmpty()

    companion object {
        /** iOS's default for `ourName`, which the backend never sends. */
        const val DEFAULT_PARTNER_NAME = "BITTR AG"
    }
}

/**
 * The bittr customer records this device holds — iOS's `bittrWallet.ibanEntities`, persisted by
 * `CacheManager` under the environment-scoped `device` key.
 *
 * ## For other features
 *
 * Anything that needs to say "which bittr customer is this device" reads [firstDepositCode]:
 * `PATCH /customer/device-token`, `POST /htlc-interceptor/ready` and the payout endpoints all key
 * on it, and iOS picks the same one — the first entity, in `order`, with a non-empty code
 * (`HandlePaymentNotification.swift`). [depositCodes] is every code, for `GET /transaction_info`.
 */
interface BittrCustomerStore {

    /** All entities, sorted by [IbanEntity.order]. */
    val entities: StateFlow<List<IbanEntity>>

    /** Insert or replace by id. */
    fun upsert(entity: IbanEntity)

    /** Apply [transform] to the entity with [id], if there is one. */
    fun update(id: String, transform: (IbanEntity) -> IbanEntity)

    /** The first non-empty deposit code, or null before signup has completed. */
    fun firstDepositCode(): String? = entities.value.firstOrNull { it.hasDepositCode }?.yourUniqueCode

    /** Every non-empty deposit code, in order. */
    fun depositCodes(): List<String> = entities.value.filter { it.hasDepositCode }.map { it.yourUniqueCode }

    /** Transaction ids already sent to `/transaction_info` — iOS's `senttobittr`. */
    fun sentToBittr(): Set<String>

    fun addSentToBittr(txIds: Collection<String>)

    /** The purchases `/transaction_info` has confirmed, keyed by tx id. */
    val purchases: StateFlow<Map<String, BittrTransactionInfo>>

    fun addPurchases(rows: Collection<BittrTransactionInfo>)
}

/**
 * [BittrCustomerStore] over one JSON file.
 *
 * The file belongs under `no_backup` and is per environment (the caller names it), matching iOS
 * scoping the cache by environment so a regtest build never shows production codes. A corrupt or
 * unreadable file reads as empty rather than throwing: iOS's `CacheStore.decoded` does the same,
 * and a crash here would take Home down with it.
 */
class FileBittrCustomerStore(private val file: File) : BittrCustomerStore {

    private val lock = Any()
    private val json = Json { ignoreUnknownKeys = true }

    private val _entities: MutableStateFlow<List<IbanEntity>>
    private val _purchases: MutableStateFlow<Map<String, BittrTransactionInfo>>
    private var sent: Set<String>

    init {
        val root = runCatching { json.parseToJsonElement(file.readText()) as? JsonObject }.getOrNull()
        _entities = MutableStateFlow(
            (root?.get("ibans") as? JsonArray).orEmpty()
                .mapNotNull { (it as? JsonObject)?.let(::decodeEntity) }
                .sortedBy { it.order },
        )
        _purchases = MutableStateFlow(
            (root?.get("purchases") as? JsonArray).orEmpty()
                .mapNotNull { (it as? JsonObject)?.let(::decodePurchase) }
                .associateBy { it.txId },
        )
        sent = (root?.get("sentToBittr") as? JsonArray).orEmpty()
            .mapNotNull { (it as? JsonPrimitive)?.content }
            .toSet()
    }

    override val entities: StateFlow<List<IbanEntity>> = _entities.asStateFlow()
    override val purchases: StateFlow<Map<String, BittrTransactionInfo>> = _purchases.asStateFlow()

    override fun upsert(entity: IbanEntity) = synchronized(lock) {
        _entities.update { list -> (list.filterNot { it.id == entity.id } + entity).sortedBy { it.order } }
        write()
    }

    override fun update(id: String, transform: (IbanEntity) -> IbanEntity) = synchronized(lock) {
        _entities.update { list -> list.map { if (it.id == id) transform(it) else it } }
        write()
    }

    override fun sentToBittr(): Set<String> = synchronized(lock) { sent }

    override fun addSentToBittr(txIds: Collection<String>) = synchronized(lock) {
        sent = sent + txIds
        write()
    }

    override fun addPurchases(rows: Collection<BittrTransactionInfo>) = synchronized(lock) {
        _purchases.update { it + rows.associateBy { row -> row.txId } }
        write()
    }

    private fun write() {
        val root = JsonObject(
            mapOf(
                "ibans" to JsonArray(_entities.value.map(::encodeEntity)),
                "purchases" to JsonArray(_purchases.value.values.map(::encodePurchase)),
                "sentToBittr" to JsonArray(sent.map(::JsonPrimitive)),
            ),
        )
        file.parentFile?.mkdirs()
        val temp = File(file.parentFile, file.name + ".tmp")
        temp.writeText(root.toString())
        if (!temp.renameTo(file)) {
            file.writeText(root.toString())
            temp.delete()
        }
    }

    internal companion object {

        private fun s(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: kotlinx.serialization.json.JsonNull

        fun encodeEntity(e: IbanEntity): JsonObject = JsonObject(
            mapOf(
                "id" to s(e.id),
                "order" to JsonPrimitive(e.order),
                "yourIbanNumber" to s(e.yourIbanNumber),
                "yourEmail" to s(e.yourEmail),
                "ourIbanNumber" to s(e.ourIbanNumber),
                "ourName" to s(e.ourName),
                "yourUniqueCode" to s(e.yourUniqueCode),
                "emailToken" to s(e.emailToken),
                "ourSwift" to s(e.ourSwift),
                "lightningAddressUsername" to s(e.lightningAddressUsername),
                "paymentMode" to s(e.paymentMode),
                "initiativeConfirmedAt" to s(e.initiativeConfirmedAt),
            ),
        )

        fun decodeEntity(o: JsonObject): IbanEntity? {
            val id = BittrEnvelope.string(o, "id") ?: return null
            return IbanEntity(
                id = id,
                order = (o["order"] as? JsonPrimitive)?.intOrNull ?: 0,
                yourIbanNumber = BittrEnvelope.string(o, "yourIbanNumber").orEmpty(),
                yourEmail = BittrEnvelope.string(o, "yourEmail").orEmpty(),
                ourIbanNumber = BittrEnvelope.string(o, "ourIbanNumber").orEmpty(),
                ourName = BittrEnvelope.string(o, "ourName") ?: IbanEntity.DEFAULT_PARTNER_NAME,
                yourUniqueCode = BittrEnvelope.string(o, "yourUniqueCode").orEmpty(),
                emailToken = BittrEnvelope.string(o, "emailToken").orEmpty(),
                ourSwift = BittrEnvelope.string(o, "ourSwift").orEmpty(),
                lightningAddressUsername = BittrEnvelope.string(o, "lightningAddressUsername").orEmpty(),
                paymentMode = BittrEnvelope.string(o, "paymentMode").orEmpty(),
                initiativeConfirmedAt = BittrEnvelope.string(o, "initiativeConfirmedAt"),
            )
        }

        private fun d(value: Double?): JsonElement = value?.let(::JsonPrimitive) ?: kotlinx.serialization.json.JsonNull

        fun encodePurchase(p: BittrTransactionInfo): JsonObject = JsonObject(
            mapOf(
                "tx_id" to s(p.txId),
                "transfer_type" to s(p.transferType),
                "historical_exchange_rate" to d(p.historicalExchangeRate),
                "datetime" to s(p.datetime),
                "currency" to s(p.currency),
                "bitcoin_amount" to d(p.bitcoinAmount),
                "fiat_amount_net" to d(p.fiatAmountNet),
                "fiat_amount_gross" to d(p.fiatAmountGross),
            ),
        )

        fun decodePurchase(o: JsonObject): BittrTransactionInfo? {
            fun num(key: String) = (o[key] as? JsonPrimitive)?.content?.toDoubleOrNull()
            return BittrTransactionInfo(
                txId = BittrEnvelope.string(o, "tx_id") ?: return null,
                transferType = BittrEnvelope.string(o, "transfer_type"),
                historicalExchangeRate = num("historical_exchange_rate"),
                datetime = BittrEnvelope.string(o, "datetime"),
                currency = BittrEnvelope.string(o, "currency"),
                bitcoinAmount = num("bitcoin_amount"),
                fiatAmountNet = num("fiat_amount_net"),
                fiatAmountGross = num("fiat_amount_gross"),
            )
        }
    }
}

/** An in-memory [BittrCustomerStore], for builds with no file to write and for tests. */
class InMemoryBittrCustomerStore(initial: List<IbanEntity> = emptyList()) : BittrCustomerStore {

    private val _entities = MutableStateFlow(initial.sortedBy { it.order })
    private val _purchases = MutableStateFlow<Map<String, BittrTransactionInfo>>(emptyMap())
    private var sent = emptySet<String>()

    override val entities: StateFlow<List<IbanEntity>> = _entities.asStateFlow()
    override val purchases: StateFlow<Map<String, BittrTransactionInfo>> = _purchases.asStateFlow()

    override fun upsert(entity: IbanEntity) =
        _entities.update { list -> (list.filterNot { it.id == entity.id } + entity).sortedBy { it.order } }

    override fun update(id: String, transform: (IbanEntity) -> IbanEntity) =
        _entities.update { list -> list.map { if (it.id == id) transform(it) else it } }

    override fun sentToBittr(): Set<String> = sent

    override fun addSentToBittr(txIds: Collection<String>) {
        sent = sent + txIds
    }

    override fun addPurchases(rows: Collection<BittrTransactionInfo>) =
        _purchases.update { it + rows.associateBy { row -> row.txId } }
}
