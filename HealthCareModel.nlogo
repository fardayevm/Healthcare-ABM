extensions [
  stats
  rnd
  table
  csv
]

breed[insurances insurance]
breed[pools pool]

insurances-own [
  marketing-exp
  adj-step-mkt
  research-exp
  accuracy-max
  accuracy-rate
  profit-margin
  history-estimated-cost
  estimated-cost
  rfp
  rfp-success
  clientele
  budget
  budget-history
  last-strategy
  recent-profit-list          ;; KS 2023-03-18
  recent-profit               ;; KS 2023-03-18
  contract-count              ;; KS 2023-03-18
  client-count                ;; KS 2023-03-18
  recent-research-expense-list
  recent-rfp-ratio-list
  rejected
]

pools-own [
  pool-size
  pool-actual-cost
  pool-estimated-cost
  insurance-provider
  pool-offer
  insurance-history
  compensation
  without-insurance
  ratio-without-insurance
]

patches-own [
  preferred-employer
  expected-cost
  true-variance
  actual-cost
  history
]

globals [
  buyers
  per-capita-exp
  percentage-without-ins
  profit-horizon         ;; KS 2023-03-18   a number (set in "setup-recent-profit") that determines how many past periods figure into "recent-profit")
]

to setup
  clear-all
  setup-insurance
  setup-pool
  setup-buyer
  recalculate-area
  get-insurances-list
  setup-budget
  setup-employee-compensation
  setup-recent-profit
  setup-recent-research-exp
  setup-market-exp
;  setup-research-exp

  setup-marketing-file
  setup-research-file
  reset-ticks
end

to go
  if ticks > 0 [
    establish-costs
    update-marketing-exp
    update-research-exp
  ]

  recalculate-area
  get-insurances-list
  calculate-estimate
  new-blood
  choose-insurance


  final-calculation
  update-compensation
  per-capita
  pools-without-insurance

  report-marketing
  report-research
  tick
end

to setup-insurance
  foreach n-of number-of-insurances base-colors [ c ->
    ask one-of patches [
      sprout 1 [
        set breed insurances
        set color c ;
        set shape "person"
        set size 3
        set profit-margin 1.05
      ]
    ]
  ]
end



to setup-buyer
  set buyers patches
  ask buyers [
;    expected cost in thousands
    set expected-cost random-poisson 25
    set true-variance random-poisson 3
    set actual-cost random-normal expected-cost true-variance
  ]
end

to setup-pool
  create-ordered-pools number-of-pools[
    set shape "circle"
    setxy random-xcor random-ycor
    set size 2
    set insurance-provider 0
  ]
  ask pools[

  ]
end

to setup-budget
  ask insurances[
    set budget ( sum [expected-cost] of buyers )
  ]
end

to setup-market-exp
  ask insurances[
    set marketing-exp budget * ( random-normal 10 2 ) * 0.001
  ]
end



to recalculate-area
    ;Have each consumer (patch) indicate its preference by
    ;taking on the color of the store it chooses
  ask pools [
   rt random-float 360
   fd rate-of-change-demographics
  ]
  ask buyers [
    set preferred-employer choose-employer
    set pcolor ([ color ] of preferred-employer + 2)
  ]
  ask pools [
    set pool-size count buyers with [preferred-employer = myself]
  ]
end


; KS 2023-03-18
to setup-recent-profit

  set profit-horizon 6           ;; This variable determines how far back insurers look to assess their profitability
  ask insurances [
    set recent-profit-list [ ]
    repeat profit-horizon [ set recent-profit-list lput random budget recent-profit-list ]
    set recent-profit mean recent-profit-list
  ]

end


to setup-recent-research-exp
  set profit-horizon 6           ;; This variable determines how far back insurers look to assess their profitability
  ask insurances [
    set research-exp budget * 0.01
    set recent-research-expense-list [ ]
    repeat profit-horizon [ set recent-research-expense-list lput ( random-normal research-exp 50) recent-research-expense-list ]
  ]

end


to setup-employee-compensation
  ask pools [
    set compensation sum [expected-cost] of buyers with [preferred-employer = myself] * 1.2
  ]
end


to new-blood
  ask buyers [
    if history = 0
    [set history preferred-employer ]

    if history != preferred-employer[

        set expected-cost random-poisson 18 + random 5
        set true-variance random-poisson 3
        set actual-cost random-normal expected-cost true-variance

        set history preferred-employer
      ]
  ]
end


to update-compensation
  ask pools[
    set compensation sum [expected-cost] of buyers with [preferred-employer = myself] * 1.6
  ]
end


; assigns 3 different insurance providers to pools' [insurance-provider] list
; Not being called on during the "go"
to get-insurances-list

; a list of insurances
  let insurance-list sort insurances
;  a list of marketing expenses
  let marketing-exp-list []

  ifelse count insurances = 1 [
    ask pools [
    set insurance-provider item 0 insurance-list
    ]
  ] [

  foreach insurance-list[ x ->
    set marketing-exp-list lput [marketing-exp] of x marketing-exp-list
  ]
; pairing insurance to marketing expense and creating a list of lists
  let pairs (map list insurance-list marketing-exp-list)
;    show pairs
;  chooses three insurances for each pool as insurance-provider
;  based on weight: function of each insurer’s marketing expenditures
  ask pools[
      ifelse number-of-insurances <= 3 [

        if number-of-insurances = 1 [
          let weight pairs
          set insurance-provider weight
        ]
        if number-of-insurances = 2 [
          let weight map first rnd:weighted-n-of-list 1 pairs  [ [p] -> last p ]
          set insurance-provider weight
        ]
        if number-of-insurances = 3 [
          let weight map first rnd:weighted-n-of-list 2 pairs  [ [p] -> last p ]
          set insurance-provider weight
        ]
       ]
      [
        let weight map first rnd:weighted-n-of-list 3 pairs  [ [p] -> last p ]
        set insurance-provider weight  ]
    ]
  ]
end

to calculate-estimate
  ask pools [

    ;let patch-dist (sum [expected-cost] of buyers with [preferred-employer = myself]) / (count buyers with [preferred-employer = myself]) * pool-size

    ;set pool-expected-cost sum [expected-cost] of buyers with [preferred-employer = myself]   ; this is an actual/expected cost needed for the whole pool

    ;set pool-variance sum [ true-variance ] of buyers with [preferred-employer = myself]           ; this is a total true-variance for the entire pool

    set pool-actual-cost sum [ actual-cost ] of buyers with [preferred-employer = myself]   ; this is the actual costs of the poolw

    let my-buyers [ actual-cost ] of buyers with [ preferred-employer = myself ]             ;selects all of buyers of the given pool


    let temp-offer []                                                                         ; created 2 temporary lists: one for offer, and the second for insurance company
    let temp-insur []

    ask insurances [
      ifelse number-of-insurances = 1 [
        let var ( [pool-actual-cost] of myself * profit-margin + marketing-exp + research-exp )
        let offer var
        set temp-offer lput offer temp-offer
        set temp-insur lput self temp-insur
      ][
      if member? self [insurance-provider] of myself = true[                                   ; checks if the given insurance has reached the pool

          ifelse ticks > 0 [
            let num-selected-buyers round (length my-buyers * accuracy-rate )                        ;generates number of buyers based on accuracy rate
            let selected-buyers n-of num-selected-buyers my-buyers                                   ;selects number of buyers based on number generated above


            ; generate new values for the remaining portion of the pool based on the acquired portion.
            let remaining-buyers (length my-buyers - num-selected-buyers)

            ; it will generate the estimate value for the pool
            ; firstly, chosen research pool will generate its sum
            ; secondly, the remaining unknown data is generated based on buyers that insurance have access
            let summa ( sum selected-buyers + ( mean selected-buyers + random-normal 0 1 ) * remaining-buyers )

            ; to the predicted pool cost the profit margin, marketing-exp, and research-exp are applied
            let var summa * profit-margin + marketing-exp + research-exp

            let offer var
            set temp-offer lput offer temp-offer
            set temp-insur lput self temp-insur

          ] [
            let var ( [pool-actual-cost] of myself * profit-margin + marketing-exp + research-exp )
            let offer var
            set temp-offer lput offer temp-offer
            set temp-insur lput self temp-insur
          ]
        ]
      ]
    ]

   set pool-offer (map list temp-offer temp-insur)                                            ; maps the the offer and insurance company that made the offer into a list
   set pool-offer sort-with [ l -> item 0 l ] pool-offer                                      ; sorts the pool's offers by the amount of the offer (low-high) - it uses report function called "sort-with"


   set temp-offer []
   set temp-insur []
  ]
end



to choose-insurance
  ask insurances [
    set rfp-success 0      ;count of how many pools chose the given insurance provider
    set rfp 0
    set clientele []   ;for a list of pools that use the given insurance provider
    set rejected 0
  ]


  ask pools [
    ;; KS 2023-02-19
    ;; What role is insurance-history playing? How does it function in the model?
    ifelse insurance-history = 0 [
      ifelse number-of-insurances <= 3 [


        if number-of-insurances = 1 [
          set insurance-history item 0 pool-offer
        ]
        if number-of-insurances = 2 [
          set insurance-history item 0 pool-offer
        ]
        if number-of-insurances = 3 [
          set insurance-history item random 2 pool-offer
        ]
      ][
      set insurance-history item random 3  pool-offer  ; randomly chooses 1 offer out of 3 offers
      ]
    ][
      ;; KS 2023-02-19
        set insurance-history item 0 pool-offer
    ]

      ;temp list for keeping estimate and related pool
      let temp-est []


      set temp-est lput item 0 insurance-history temp-est        ; inputs estimate amount into a list above
      set temp-est lput self temp-est                            ; inputs related pool into a list above


      ask insurances [
        ifelse number-of-insurances = 1 [
          set rfp number-of-pools
          set rfp-success number-of-pools

          set clientele lput temp-est clientele
        ] [

          if member? self [insurance-provider] of myself = true[
            set rfp rfp + 1
          ]

          if member? self [insurance-history] of myself = true[           ;checks if insurance matches with the one randomly chosen
            set rfp-success rfp-success + 1                               ; if yes, rfp-history increments by one. it will be useful to generate marketing expenses

            set clientele lput temp-est clientele                         ; inputs temporary list into clientele list.
                                                                          ; thus, insurance companies now have all received and accepted offers inside one list called clientele
          ]
        ]
      ]
      set temp-est []

      let possible-offer item 0 (item 0 pool-offer)
      if possible-offer > compensation [
        if random-float 1 < 0.8 [
          set insurance-history []

          ask insurances [
            if self = item 1 item 0 [ pool-offer] of myself[
              set rejected rejected + 1

            ]
          ]
        ]
      ]
    ]


end




to establish-costs
  ask buyers [
    set expected-cost random-poisson 25
    set true-variance random-poisson 3

    set actual-cost random-normal expected-cost true-variance
  ]
end

to-report choose-employer
  report min-one-of pools [(distance myself)]
end

to-report sort-with [ key lst ]
  report sort-by [ [a b] -> (runresult key a) < (runresult key b) ] lst
end




to update-marketing-exp
  ask insurances [
    ifelse number-of-insurances = 1 [
      let success-mkt 1

      let target-success-mkt 0.7

      let gradient (target-success-mkt - success-mkt) * 0.06                    ; gradient optimization

      if marketing-exp <= budget * 0.05 [
        set marketing-exp marketing-exp + gradient * marketing-exp
     ]
    ][
      let success-mkt ifelse-value (rfp = 0) [0] [rfp / count pools]

      ; gradient 1
      let target-success-mkt 0.7
      let gradient-01 (target-success-mkt - success-mkt) * marketing-exp               ; gradient optimization

      ; gradient 2
      ; epilson correction
      let rfp-success-corrected rfp-success
      if rfp-success-corrected = 0 [
        set rfp-success-corrected rfp-success-corrected + 0.00000001
      ]


      let failed-contracts-ratio rejected / rfp-success-corrected
      let gradient-02 failed-contracts-ratio * marketing-exp

      let slope ( budget / budget-history ) / abs (budget / budget-history)

      ifelse marketing-exp <= abs budget * 0.05 [
        if budget > 0 [
          set marketing-exp marketing-exp + ln(abs gradient-01 + 1)
          if failed-contracts-ratio > 0.05 [
            set marketing-exp marketing-exp - ln(abs gradient-02 + 1)
          ]
        ]

        if budget < 0 [

          ifelse failed-contracts-ratio > 0.05 or rfp-success <  2[
            ifelse failed-contracts-ratio != 0
                [ set marketing-exp marketing-exp - ln(abs gradient-02 + 1)]
                [ set marketing-exp marketing-exp - ln(abs marketing-exp + 1)]
          ][set marketing-exp marketing-exp + ln(abs gradient-01 + 1)]
        ]

      ][set marketing-exp marketing-exp - 10 * ln( abs marketing-exp + 1) * slope
        print ln( abs marketing-exp + 1)
      ]

    ]
  ]
end


to update-research-exp
  ask insurances [
    set accuracy-max 0.95

    let research-exp-scaled ( research-exp / (count buyers) )
    let accuracy (1 / (1 + exp( - research-exp-scaled )))
    set accuracy-rate min list accuracy accuracy-max

    let rfp-success-corrected rfp-success
      if rfp-success-corrected = 0 [
        set rfp-success-corrected rfp-success-corrected + 0.00000001
      ]


    let failed-contracts-ratio rejected / rfp-success-corrected

    ; Implement AI algorithm to calculate new gradient based on recent profits and recent research expenses
    let difference linear-regression recent-profit-list recent-research-expense-list
    let slope ( budget / budget-history )

    let new-gradient difference * (recent-profit / (abs recent-profit))




    if failed-contracts-ratio > 0.05 [
      ifelse failed-contracts-ratio != 0 [
        if research-exp <= abs budget * 0.05 [
          if budget > 0 [
            ifelse research-exp > 0 [
              if number-of-insurances = 2 [
                set research-exp research-exp + new-gradient * 0.01
              ]
              if number-of-insurances = 3 [
                set research-exp research-exp + new-gradient * 0.02
              ]
              if number-of-insurances = 4 [
                set research-exp research-exp + new-gradient * 0.03
              ]
              if number-of-insurances = 5 [
                set research-exp research-exp + new-gradient * 0.04
              ]
              if number-of-insurances = 6 [
                set research-exp research-exp + new-gradient * 0.05
              ]
            ][
              set research-exp 1
            ]
          ]

        if budget < 0 [
          if failed-contracts-ratio > 0.05 or rfp-success <  2[
             set marketing-exp marketing-exp - ln(abs new-gradient + 1)
          ]
        ]
      ]
    ][ set research-exp research-exp - ln(abs research-exp + 1) * slope]
    update-recent-data
  ]
  ]
end

; Linear regression function
to-report linear-regression [x y]
  let n length x
  let sum-x sum x
  let sum-y sum y
  let sum-xy sum ( map [ [xs ys] -> xs * ys ] x y)
  let sum-x-squared sum ( map [ [xs] -> xs * xs ] x)
  let denom (n * sum-x-squared - sum-x * sum-x)

  ifelse denom = 0
  [
    report 0
  ]
  [
    let beta ((n * sum-xy - sum-x * sum-y) / denom )
    let alpha (sum-y - beta * sum-x) / n

    let last-profit last recent-profit-list
    let optimal-research-exp ( alpha +  beta * ( last-profit))
    report optimal-research-exp
  ]
end


to update-recent-data
  set recent-profit-list lput (budget - budget-history) recent-profit-list
  set recent-research-expense-list lput research-exp recent-research-expense-list
;  set recent-rfp-ratio-list lput (rfp-success / rfp ) recent-rfp-ratio-list

  if length recent-profit-list > 5 [
    set recent-profit-list but-first recent-profit-list
  ]
  if length recent-research-expense-list > 5 [
    set recent-research-expense-list but-first recent-research-expense-list
  ]
;  if length recent-rfp-ratio-list > 5 [
;    set recent-rfp-ratio-list but-first recent-rfp-ratio-list
;  ]
end




; this function runs the final calculations and updates budget information of insurances
to final-calculation
  ; current budget info is saved as budget-history.

    ask insurances [
      ;; KS 2023-02-19
      ;; so "budget-history" is simply the previous period's budget?


      ;; KS 2023-03-18 updating of recent-profit-list, calculation of recent-profit
      ;    set recent-profit-list lput (budget - budget-history) recent-profit-list
      ;    while [ length recent-profit-list > profit-horizon ] [
      ;      set recent-profit-list but-first recent-profit-list
      ;    ]

      set recent-profit mean recent-profit-list
      set budget-history budget

      ;; KS 2023-03-18 tracking how many contracts and clients each insurer has

;      let my-customers turtle-set pools with [ item 1 insurance-history = myself ]
;      show ( word who " my-customers: " my-customers )
;      set contract-count length clientele
;      set client-count 0
;      if any? my-customers [
;        set client-count sum [ pool-size ] of my-customers
;      ]
    ]


    ask pools [
    if insurance-history != [] [
      ; estimate that pool received and accepted
      let estimate item 0 insurance-history

      ; difference between the estimate and the actual cost
      let difference estimate - pool-actual-cost
      if difference < 0 [
        show ( word "Negative outcome - tick: " ticks "; estimate: " estimate "; actual: " pool-actual-cost )
      ]

      ;the budget is updated every time pool accepts certain offer from the insurance.
      ask insurances [
        ; this line checks if the pool's insurance provider matches
        if self = item 1 [insurance-history] of myself [
          ;        show (word "Insurer " [ who ] of self " budget before adding difference: " budget )       ;;  KS 2023-03-17 - trying to understand evolution of budget better
          set budget budget + difference
          ;        show (word "Insurer " [ who ] of self " budget after adding difference: " budget )       ;;  KS 2023-03-17 - trying to understand evolution of budget better
        ]

      ]
    ]
    ]

    ask insurances [
      ;    show (word "Insurer " who " budget before deducting expenses: " budget )       ;;  KS 2023-03-17 - trying to understand evolution of budget better
      set budget budget - marketing-exp - research-exp
      ;    show (word "Insurer " who " budget after deducting expenses: " budget )       ;;  KS 2023-03-17 - trying to understand evolution of budget better
    ]


end



to pools-without-insurance
  let temp-num 0
  ask pools [
    if insurance-history = [][
    set temp-num temp-num + 1
    ]
  ]
  set percentage-without-ins ( 1 - temp-num / number-of-pools ) * 100
end

to per-capita                      ; this function returns per capita expense

  set per-capita-exp 0

  ask pools [
    if insurance-history != [] [
    let var item 0 insurance-history
    set per-capita-exp per-capita-exp + var
    ]
  ]

  set per-capita-exp per-capita-exp / count buyers
end


to setup-marketing-file
  if (file-exists? "marketing_data.csv")
  [
    carefully
      [file-delete "marketing_data.csv"]
    [ print error-message ]
  ]
  file-open "marketing_data.csv"

  file-type "tick,"
  file-type "insurance_id,"
  file-type "marketing_exp,"
  file-print "rfp,"

  file-close
end

to report-marketing
  file-open "marketing_data.csv"
  foreach sort insurances [ n ->
    ask n [
      file-type word ticks ","
      file-type word who ","
      file-type word marketing-exp ","
      file-print word rfp ","
    ]
  ]

  file-close
end

to setup-research-file
  if (file-exists? "research_data.csv")
  [
    carefully
      [file-delete "research_data.csv"]
    [ print error-message ]
  ]
  file-open "research_data.csv"

  file-type "tick,"
  file-type "insurance_id,"
  file-type "research_exp,"
  file-print "accuracy_rate,"

  file-close
end

to report-research
  file-open "research_data.csv"
  foreach sort insurances [ n ->
    ask n [
      file-type word ticks ","
      file-type word who ","
      file-type word research-exp ","
      file-print word accuracy-rate ","
    ]
  ]

  file-close
end
















































@#$#@#$#@
GRAPHICS-WINDOW
271
10
812
552
-1
-1
13.0
1
10
1
1
1
0
0
0
1
-20
20
-20
20
0
0
1
ticks
30.0

BUTTON
29
12
92
45
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
94
12
157
45
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
32
57
220
90
number-of-insurances
number-of-insurances
1
6
4.0
1
1
NIL
HORIZONTAL

BUTTON
159
13
225
46
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
41
100
213
133
number-of-pools
number-of-pools
8
14
10.0
2
1
NIL
HORIZONTAL

SLIDER
9
144
249
177
rate-of-change-demographics
rate-of-change-demographics
0
1
0.2
0.2
1
NIL
HORIZONTAL

PLOT
31
244
231
394
Per Capita Expense
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"default" 1.0 0 -955883 true "" "plot per-capita-exp"

PLOT
1178
20
1478
188
marketing-exp of insurances
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Ins-0" 1.0 0 -16777216 true "" "plot [ marketing-exp ] of insurance 0"
"Ins-1" 1.0 0 -2674135 true "" "plot [ marketing-exp ] of insurance 1"
"Ins-2" 1.0 0 -1184463 true "" "plot [ marketing-exp ] of insurance 2"
"Ins-3" 1.0 0 -13791810 true "" "plot [ marketing-exp ] of insurance 3"
"Ins-4" 1.0 0 -7500403 true "" "plot [ marketing-exp ] of insurance 4"
"Ins-5" 1.0 0 -955883 true "" "plot [ marketing-exp ] of insurance 5"

PLOT
1178
193
1475
343
insurers' profits
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Ins-0" 1.0 0 -16777216 true "" "if ticks > 6 [ plot [ recent-profit ] of insurance 0 ]"
"Ins-1" 1.0 0 -2674135 true "" "if ticks > 6 [ plot [ recent-profit ] of insurance 1 ]"
"Ins-2" 1.0 0 -1184463 true "" "if ticks > 6 [ plot [ recent-profit ] of insurance 2 ]"
"Ins-3" 1.0 0 -13791810 true "" "if ticks > 6 [ plot [ recent-profit ] of insurance 3 ]"
"Ins-4" 1.0 0 -7500403 true "" "if ticks > 6 [ plot [ recent-profit ] of insurance 4 ]"
"Ins-5" 1.0 0 -955883 true "" "if ticks > 6 [ plot [ recent-profit ] of insurance 5 ]"

PLOT
856
20
1168
190
Research
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Ins-0" 1.0 0 -16777216 true "" "plot [ research-exp ] of insurance 0"
"Ins-1" 1.0 0 -2674135 true "" "plot [ research-exp ] of insurance 1"
"Ins-2" 1.0 0 -1184463 true "" "plot [ research-exp ] of insurance 2"
"Ins-3" 1.0 0 -13791810 true "" "plot [ research-exp ] of insurance 3"
"Ins-4" 1.0 0 -7500403 true "" "plot [ research-exp ] of insurance 4"
"Ins-5" 1.0 0 -955883 true "" "plot [ research-exp ] of insurance 5"

PLOT
823
194
1173
344
Pools Covered (Percentage)
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Ins-0" 1.0 0 -16777216 true "" "plot percentage-without-ins"

PLOT
1185
354
1475
504
budgets of insurers
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Ins-0" 1.0 0 -16777216 true "" "plot [ budget ] of insurance 0"
"pen-1" 1.0 0 -2674135 true "" "plot [ budget ] of insurance 1"
"pen-2" 1.0 0 -1184463 true "" "plot [ budget ] of insurance 2"
"pen-3" 1.0 0 -13791810 true "" "plot [ budget ] of insurance 3"
"pen-4" 1.0 0 -7500403 true "" "plot [ budget ] of insurance 4"
"pen-5" 1.0 0 -955883 true "" "plot [ budget ] of insurance 5"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.3.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
