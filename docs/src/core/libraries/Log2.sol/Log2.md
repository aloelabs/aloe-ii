# Log2

<pre>
log_2(x) = log_2(2^n · y)                                         |  n ∈ ℤ, y ∈ [1, 2)
         = log_2(2^n) + log_2(y)
         = n + log_2(y)
           ┃     ║
           ┃     ║  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
           ┗━━━━━╫━━┫ n = ⌊log_2(x)⌋                ┃
                 ║  ┃   = most significant bit of x ┃
                 ║  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                 ║
                 ║  ╔════════════════════════════════════════════════════════════════╗
                 ╚══╣ Iterative Approximation:                                       ║
                    ║ ↳ goal: solve log_2(a) | a ∈ [1, 2)                            ║
                    ║                                                                ║
                    ║ log_2(a) = ½log_2(a^2)                                         ║
                    ║          = ½⌊log_2(a^2)⌋ - ½⌊log_2(a^2)⌋ + ½log_2(a^2)         ║
                    ║                                                                ║
                    ║                                              ⎧ 0   for a^2 < 2 ║
                    ║ a ∈ [1, 2)  ⇒  a^2 ∈ [1, 4)  ∴  ⌊log_2(a^2)⌋ ⎨                 ║
                    ║                                              ⎩ 1   for a^2 ≥ 2 ║
                    ║                                                                ║
                    ║ if a^2 < 2                                                     ║
                    ║ ┌────────────────────────────────────────────────────────────┐ ║
                    ║ │ log_2(a) = ½⌊log_2(a^2)⌋ - ½⌊log_2(a^2)⌋ + ½log_2(a^2)     │ ║
                    ║ │          = ½⌊log_2(a^2)⌋ - ½·0 + ½log_2(a^2)               │ ║
                    ║ │          = ½⌊log_2(a^2)⌋ + ½log_2(a^2)                     │ ║
                    ║ │                                                            │ ║
                    ║ │ (Yes, 1st term is just 0. Keeping it as-is for fun.)       │ ║
                    ║ │ a^2 ∈ [1, 4)  ^  a^2 < 2  ∴  a^2 ∈ [1, 2)                  │ ║
                    ║ └────────────────────────────────────────────────────────────┘ ║
                    ║                                                                ║
                    ║ if a^2 ≥ 2                                                     ║
                    ║ ┌────────────────────────────────────────────────────────────┐ ║
                    ║ │ log_2(a) = ½⌊log_2(a^2)⌋ - ½⌊log_2(a^2)⌋ + ½log_2(a^2)     │ ║
                    ║ │          = ½⌊log_2(a^2)⌋ - ½·1 + ½log_2(a^2)               │ ║
                    ║ │          = ½⌊log_2(a^2)⌋ + ½log_2(a^2) - ½                 │ ║
                    ║ │          = ½⌊log_2(a^2)⌋ + ½(log_2(a^2) - 1)               │ ║
                    ║ │          = ½⌊log_2(a^2)⌋ + ½(log_2(a^2) - log_2(2))        │ ║
                    ║ │          = ½⌊log_2(a^2)⌋ + ½log_2(a^2 / 2)                 │ ║
                    ║ │                                                            │ ║
                    ║ │ (Yes, 1st term is just ½. Keeping it as-is for fun.)       │ ║
                    ║ │ a^2 ∈ [1, 4)  ^  a^2 ≥ 2  ∴  a^2 / 2 ∈ [1, 2)              │ ║
                    ║ └────────────────────────────────────────────────────────────┘ ║
                    ║                                                                ║
                    ║ ↳ combining...                                                 ║
                    ║                                                                ║
                    ║                              ⎧ log_2(a^2)       for a^2 < 2    ║
                    ║ log_2(a) = ½⌊log_2(a^2)⌋ + ½·⎨                                 ║
                    ║                              ⎩ log_2(a^2 / 2)   for a^2 ≥ 2    ║
                    ║                                                                ║
                    ║ ↳ works out nicely! as shown above, the arguments of the       ║
                    ║   final log_2 (a^2 and a^2 / 2, respectively) are in the       ║
                    ║   range [1, 2)  ⇒  run the algo recursively. Each step adds    ║
                    ║   1 bit of precision to the result.                            ║
                    ╚════════════════════════════════════════════════════════════════╝
</pre>
