breed[areas area]
breed[taxis taxi]

areas-own[next-location current-queue charging-taxi]
taxis-own[current-location destination route next-area state battery] ;state will contain a string "available" "hired" or "charging" "queuing"


globals[temp-destination dist full-charge]

extensions [csv array table]

to setup
  ca
  reset-ticks
  import-drawing "world.png"
  setup-areas
  setup-link
  setup-taxis
end

to go
  ask taxis[
    ; if current position/patch is not on item 0 route, then move, else pop item 0 set next-destination item 0

    ;Each area will have a queue
    ; If available and below threshold, charge the vehicle. it will be naturally be in one of the square
    ; joins the queue in the station

    ; Taxi is currently available and waiting for a passenger
    if state = "available" [
      ifelse battery > low-battery-threshold
      [ ; battery above the threshold, getting hired
        if random 100 < hire-probability[
          set destination ([who] of one-of areas) ;randomise goal-destination ([who] of a random area)
          ; TODO: set the route to the goal-destination using a* (current-location, goal-destination)
          ;set route a-star[current-location][destination]
          set route (a-star current-location destination)
;          show "getting hired"
          set state "hired"
          set label state
;          show state
        ]
      ]
      [ ; battery below the threshold, join the area queue to which it is on
        let current-area one-of areas-on self
        let current-taxi self
        ask current-area [ set current-queue insert-item (length current-queue) current-queue current-taxi ]
        set state "queuing"
        set label state
      ]

    ]

    ; Taxi being hired and en route to destination
    if state = "hired"[
      ifelse not empty? route
      [ ; if taxi has not reached the goal-destination, continue to move
        set next-area area item 0 route
        set heading towards next-area
        let x-cor [xcor] of next-area
        let y-cor [ycor] of next-area
        fd 1
        set battery battery - battery-consumption-rate
        ifelse battery < 0 [ set color black set state "breakdown" set label state] [
          if round(xcor) = x-cor and round(ycor) = y-cor[
          set route remove-item 0 route setxy x-cor y-cor
          set current-location ([who] of next-area)
;          show current-location
          ]
        ]


      ]
      [ ; if taxi reached the goal-destination, change state to "available"
        set state "available"
        set label state
      ]
    ]
  ]

  ask areas[
    let charge-list []
    let current-area self
    ifelse length current-queue > num-charging-stations-per-area[
      set charge-list sublist current-queue 0 num-charging-stations-per-area
    ]
    [
      set charge-list current-queue
    ]
    foreach charge-list [
      x -> ask x [
        ifelse full-charge - battery <= charge-rate
        [
          set state "available"
          set label state
          set battery full-charge
          ask current-area[set current-queue remove x current-queue]
;          show battery
        ]
        [
          set state "charging"
          set label state
          set battery battery + charge-rate
;          show battery
        ]
      ]
    ]
  ]
  tick
end

to setup-areas
  create-areas 39 ;;39 areas in this world given 39 districts
  ask areas [set color red set size 1.5 set shape "square" set label who set current-queue [] ]
  ;; sets the areas according to their respective coordinates derived from the excel sheet
  file-open "coordinates.csv"
  let data csv:from-file "coordinates.csv"
  (foreach data [
    [lst] -> ask area item 0 lst [setxy item 1 lst item 2 lst]])
end

to setup-link
  file-open "links.csv"
  let the-links csv:from-file "links.csv"
  (foreach the-links[
    [lst] -> ask area item 0 lst [create-link-with area item 1 lst]])
  ask links[set color blue set thickness 0.3]

end

to setup-taxis
  set full-charge (battery-capacity * charging-completion-threshold / 100)
  create-taxis num-taxis [
    let temp-area one-of areas
    set color green
    set size 2.5
    move-to temp-area
    set battery battery-capacity
    set state "available"
    set label state
    set current-location ([who] of temp-area)
  ]
end

to-report a-star [start goal]
;  show (word "start: " start "; goal: " goal)

  let closed-set []  ;evaluated nodes

  let open-set []  ;nodes not evaluated yet
  set open-set lput start open-set  ;initially, only start in the open-set

  let came-from table:make  ;contain most efficient previous step

  let g-score table:make  ;for each node, cost of getting from start node to that node
  table:put g-score start 0  ;cost from start to start is 0

  let f-score table:make  ;for each node, cost of getting from start node to goal
  table:put f-score start calculate-h start goal  ;first node, f score is only h-value since g is 0

;  show (word "closed-set: " closed-set "; open-set: " open-set "; came-from: " came-from)
;  show (word "g-score: " g-score "; f-score: " f-score)

  while [length open-set > 0] [
    let current ""

    ;find the node in open-set with the lowest f-score
    let min-f-score 99999
    foreach open-set [ node ->
      let node-f-score table:get f-score node
      if node-f-score < min-f-score [ set current node set min-f-score node-f-score] ]
;    show (word "current: " current)

    ;terminate if current is the goal
    if current = goal [
;      show "Done"
      report reconstruct-path came-from current]

    set open-set remove current open-set  ;remove current from open-set
    set closed-set lput current closed-set  ;add current to closed-set

    ;get neighbor of current node
    let neighbors-current []
    ask area current [ ask link-neighbors [set neighbors-current lput who neighbors-current] ]
;    show (word "neighbors-current: " neighbors-current)

    ;loop through each neighbor
    foreach neighbors-current [ neighbor ->
      if not member? neighbor closed-set [
        let tentative-gscore ((table:get g-score current) + (distance-betw current neighbor))
        ifelse not member? neighbor open-set [
          set open-set lput neighbor open-set
          table:put came-from neighbor current
          table:put g-score neighbor tentative-gscore
          table:put f-score neighbor ((table:get g-score neighbor) + (calculate-h neighbor goal))
        ] [
          if tentative-gscore < (table:get g-score neighbor) [
            table:put came-from neighbor current
            table:put g-score neighbor tentative-gscore
            table:put f-score neighbor ((table:get g-score neighbor) + (calculate-h neighbor goal))
          ]
        ]

      ]
    ]
  ]
end

to-report reconstruct-path [came-from current]
  let total-path []
  set total-path lput current total-path
  while [member? current table:keys came-from] [
    set current table:get came-from current
    set total-path fput current total-path
  ]
  set total-path remove-item 0 total-path
;  show (word "Total Path: " total-path)
  report total-path
end

to-report distance-betw [start-node end-node]
  let dist-between 0
  ask area start-node[
    set temp-destination area end-node
    set dist-between distance temp-destination
  ]
  set dist-between precision dist-between 4
;  show (word "CALCULATE DISTANCE: from " start-node " to " end-node " ==> " dist-between)
  report dist-between
end

to-report calculate-h [start-node end-node]
  let h-value 0
  ask area start-node[
    set temp-destination area end-node
    set h-value distance temp-destination
  ]
  set h-value precision h-value 4
;  show (word "CALCULATE H-VALUE: from " start-node " to " end-node " ==> " h-value)
  report h-value
end


@#$#@#$#@
GRAPHICS-WINDOW
920
13
1573
386
-1
-1
6.39
1
10
1
1
1
0
1
1
1
-50
50
-28
28
0
0
1
ticks
30.0

BUTTON
17
27
83
60
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

BUTTON
101
28
164
61
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

SLIDER
16
79
289
112
num-taxis
num-taxis
0
3000
2010.0
1
1
NIL
HORIZONTAL

SLIDER
16
165
289
198
battery-capacity
battery-capacity
0
500
500.0
1
1
NIL
HORIZONTAL

SLIDER
14
211
288
244
low-battery-threshold
low-battery-threshold
0
500
154.0
1
1
NIL
HORIZONTAL

SLIDER
16
124
288
157
hire-probability
hire-probability
0
100
70.0
1
1
%
HORIZONTAL

SLIDER
14
256
289
289
charge-rate
charge-rate
0
100
20.0
1
1
NIL
HORIZONTAL

SLIDER
14
299
289
332
num-charging-stations-per-area
num-charging-stations-per-area
0
20
2.0
1
1
NIL
HORIZONTAL

BUTTON
180
29
243
62
go
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
14
341
289
374
battery-consumption-rate
battery-consumption-rate
0
20
1.0
1
1
NIL
HORIZONTAL

MONITOR
460
215
573
260
Available Count
count taxis with [state = \"available\"]
17
1
11

MONITOR
585
217
674
262
Hired Count
count taxis with [state = \"hired\"]
17
1
11

MONITOR
682
217
791
262
Queuing Count
count taxis with [state = \"queuing\"]
17
1
11

MONITOR
798
217
911
262
Charging Count
count taxis with [state = \"charging\"]
17
1
11

PLOT
458
13
911
207
Plot of Taxis' State Count
Time
Count
0.0
0.0
0.0
30.0
true
true
"" ""
PENS
"available taxis" 1.0 0 -13840069 true "plot count taxis with [state = \"available\"]" "plot count taxis with [state = \"available\"]"
"hired taxis" 1.0 0 -16710398 true "plot count taxis with [state = \"available\"]" "plot count taxis with [state = \"hired\"]"
"queuing taxis" 1.0 0 -2674135 true "plot count taxis with [state = \"available\"]" "plot count taxis with [state = \"queuing\"]"
"charging taxis" 1.0 0 -13791810 true "plot count taxis with [state = \"available\"]" "plot count taxis with [state = \"charging\"]"

SLIDER
14
385
292
418
charging-completion-threshold
charging-completion-threshold
0
100
100.0
1
1
%
HORIZONTAL

MONITOR
458
273
665
318
Average Battery Charge
mean [battery] of taxis
2
1
11

MONITOR
788
268
910
313
Breakdown Count
count taxis with [state = \"breakdown\"]
17
1
11

MONITOR
457
331
719
376
Mean Queue Length
mean ([length current-queue] of areas)
17
1
11

@#$#@#$#@
## WHAT IS IT?

This model is to simulate electric taxis in Singapore and the respective charging stations. 

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
NetLogo 6.0.4
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
