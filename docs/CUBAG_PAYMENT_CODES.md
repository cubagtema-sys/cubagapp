# CUBAG payment codes for WhitsunPay settlement

All CUBAG MoMo payments are collected into **one WhitsunPay merchant account**.
Each payment's narration (the `description` field in the WhitsunPay payment request)
starts with one or more **payment codes and amounts**. WhitsunPay should settle each
amount into the CUBAG bank account registered for its code.

**Each code always settles into exactly one account.** Several codes can share an account.

## Codes and settlement accounts

> CUBAG must confirm the account names and numbers below before go-live.

| Code | What it is for | Bank | Account number |
|---|---|---|---|
| `CUB-REG` | New member registration (registration, vetting, clearing and forwarding fee, association cloth) | GCB | 107113005326 |
| `CUB-SUB` | Subscription fees and development levy | Zenith Bank | 6010309212 |
| `CUB-ADM` | Administrative, legal and audit, welfare, consolidation, ID card, SIC bond | GCB | 107113005326 |
| `CUB-DST` | District registration, district clearance, district welfare | Ecobank | 1441002452360 |
| `CUB-CPD` | CPD and refresher courses | NIB | 1110045585101 |
| `CUB-CTI` | CUBAG Training Institute courses (members and guests) | NIB | 1110045585101 |
| `CUB-GST` | Public and guest services | GCB | 107113005326 |
| `CUB-OTH` | Anything not matched to a fee (should be rare) | GCB | 107113005326 |

CUBAG admins can give a fee a different code in **Admin → Fees** (for example to split
legal and audit fees from administrative fees). The system refuses a code that would
point at two different accounts.

## Narration format

```
<CODE> <AMOUNT>, <CODE> <AMOUNT>, ... | <TRANSACTION REFERENCE> | <PURPOSE>
```

- Codes and amounts always come first and are never shortened.
- Amounts are in cedis with two decimals, and **always add up to the transaction amount**.
- The whole narration is at most 120 characters.

Examples:

| Payment | Narration |
|---|---|
| Renewal, small company, Tema district (GH₵ 783.00) | `CUB-SUB 233.00, CUB-ADM 300.00, CUB-DST 250.00 \| CUBAG-42-ab12cd34 \| Annual Renewal Dues` |
| ID card on its own (GH₵ 45.00) | `CUB-ADM 45.00 \| CUBAG-57-9f3e21aa \| ID card` |
| Guest course enrolment (GH₵ 1,500.00) | `CUB-CTI 1500.00 \| CTI-20261115-4F2A1B \| CTI: Customs Declarations & ICUMS 2.0` |

The same codes and amounts are also sent in `metadata.payment_codes` as a list of
`{code, amount, bank_name, account_number}`.

## Questions for WhitsunPay

1. Can one transaction be settled into several accounts, using the codes and amounts in the narration (or in `metadata.payment_codes`)? If not, which format do you need?
2. Is there a length limit on `description`? We keep it to 120 characters.
3. Are the codes and amounts returned in your settlement reports and payment-status webhooks?
4. How often is settlement made (daily, weekly), and in what report format?

## Checking settlements

CUBAG finance can see what each account should receive in **Admin → Revenue → Settlement**:
totals per bank and per code for any period, with a CSV download. Payments made by bank
deposit or at the office are counted separately; they are not settled by WhitsunPay.
