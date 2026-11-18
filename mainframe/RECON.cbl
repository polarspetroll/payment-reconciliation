       IDENTIFICATION DIVISION.
       PROGRAM-ID. RECON.
      * v2 reconciliation, same rules as sql/03_rules_v2.sql
      * both inputs sorted by reference (JCL step 1) so all lines
      * of a payment come together. one pass over the files, each
      * reference group gets matched in memory and written out
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT LEDGA  ASSIGN TO LEDGERA.
           SELECT LEDGB  ASSIGN TO LEDGERB.
           SELECT MATCHF ASSIGN TO MATCHED.
           SELECT UNMA   ASSIGN TO UNMATCHA.
           SELECT UNMB   ASSIGN TO UNMATCHB.
           SELECT MISF   ASSIGN TO MISMATCH.
       DATA DIVISION.
       FILE SECTION.
       FD  LEDGA RECORDING MODE F.
       01  LEDGA-REC            PIC X(100).
       FD  LEDGB RECORDING MODE F.
       01  LEDGB-REC            PIC X(100).
       FD  MATCHF RECORDING MODE F.
       01  MATCH-REC.
           05 MR-A-ID           PIC X(10).
           05 MR-B-ID           PIC X(10).
           05 MR-REF            PIC X(16).
           05 MR-AMOUNT         PIC 9(11)V99.
           05 MR-DATE           PIC X(8).
           05 MR-RULE           PIC X.
           05 FILLER            PIC X(22).
       FD  UNMA RECORDING MODE F.
       01  UNMA-REC             PIC X(100).
       FD  UNMB RECORDING MODE F.
       01  UNMB-REC             PIC X(100).
       FD  MISF RECORDING MODE F.
       01  MIS-REC.
           05 MS-LEDGER         PIC X.
           05 MS-DATA           PIC X(100).

       WORKING-STORAGE SECTION.
       01  WS-A.
           COPY PAYREC.
       01  WS-B.
           COPY PAYREC.
       01  KA-REF               PIC X(16).
       01  KB-REF               PIC X(16).
       01  CUR-REF              PIC X(16).

      * one reference group. A = bank lines, B = erp records
      * status: space open, D dup, W window match, S split,
      *         A amount mismatch, C wrong counterparty, M missing
       01  GRP-A.
           05 NA                PIC 9(4) COMP VALUE 0.
           05 GA OCCURS 50 TIMES.
              10 GA-REC.
                 15 GA-ID       PIC X(10).
                 15 GA-DATE     PIC 9(8).
                 15 GA-AMT      PIC 9(11)V99.
                 15 GA-CCY      PIC X(3).
                 15 GA-CPTY     PIC X(40).
                 15 GA-REF      PIC X(16).
                 15 GA-SRC      PIC X(7).
                 15 GA-RSN      PIC X.
                 15 FILLER      PIC X(2).
              10 GA-DAY         PIC S9(9) COMP.
              10 GA-ST          PIC X.
              10 GA-WITH        PIC 9(4) COMP.
              10 GA-BEST        PIC 9(4) COMP.
       01  GRP-B.
           05 NB                PIC 9(4) COMP VALUE 0.
           05 GB OCCURS 50 TIMES.
              10 GB-REC.
                 15 GB-ID       PIC X(10).
                 15 GB-DATE     PIC 9(8).
                 15 GB-AMT      PIC 9(11)V99.
                 15 GB-CCY      PIC X(3).
                 15 GB-CPTY     PIC X(40).
                 15 GB-REF      PIC X(16).
                 15 GB-SRC      PIC X(7).
                 15 GB-RSN      PIC X.
                 15 FILLER      PIC X(2).
              10 GB-DAY         PIC S9(9) COMP.
              10 GB-ST          PIC X.
              10 GB-WITH        PIC 9(4) COMP.
              10 GB-BEST        PIC 9(4) COMP.

       01  WK.
           05 I                 PIC 9(4) COMP.
           05 J                 PIC 9(4) COMP.
           05 K                 PIC 9(4) COMP.
           05 PHASE              PIC X.
           05 OK                PIC X.
           05 LEADER            PIC X.
           05 DD                PIC S9(9) COMP.
           05 AD                PIC S9(13)V99 COMP-3.
           05 K1                PIC S9(13)V99 COMP-3.
           05 K2                PIC S9(13)V99 COMP-3.
           05 BK1               PIC S9(13)V99 COMP-3.
           05 BK2               PIC S9(13)V99 COMP-3.
           05 BEST-ID           PIC X(10).
           05 BEST-IX           PIC 9(4) COMP.
           05 CNT               PIC 9(4) COMP.
           05 TOT               PIC S9(13)V99 COMP-3.
           05 D1                PIC S9(9) COMP.
           05 D2                PIC S9(9) COMP.

       01  COUNTERS.
           05 READ-A            PIC 9(9) COMP VALUE 0.
           05 READ-B            PIC 9(9) COMP VALUE 0.
           05 GROUPS            PIC 9(9) COMP VALUE 0.
           05 CNT-WIN           PIC 9(9) COMP VALUE 0.
           05 CNT-SPLA          PIC 9(9) COMP VALUE 0.
           05 CNT-SPLB          PIC 9(9) COMP VALUE 0.
           05 CNT-DUPA          PIC 9(9) COMP VALUE 0.
           05 CNT-DUPB          PIC 9(9) COMP VALUE 0.
           05 CNT-MISSA         PIC 9(9) COMP VALUE 0.
           05 CNT-MISSB         PIC 9(9) COMP VALUE 0.
           05 CNT-MISA          PIC 9(9) COMP VALUE 0.
           05 CNT-MISB          PIC 9(9) COMP VALUE 0.
       01  TOTALS.
           05 AMT-MATCH         PIC S9(13)V99 COMP-3 VALUE 0.
           05 AMT-UNMA          PIC S9(13)V99 COMP-3 VALUE 0.
           05 AMT-UNMB          PIC S9(13)V99 COMP-3 VALUE 0.
           05 AMT-MIS           PIC S9(13)V99 COMP-3 VALUE 0.
       01  OUT-CNT              PIC ZZZ,ZZZ,ZZ9.
       01  OUT-AMT              PIC ZZZ,ZZZ,ZZZ,ZZ9.99.

       PROCEDURE DIVISION.
       MAIN-PARA.
           OPEN INPUT LEDGA LEDGB
                OUTPUT MATCHF UNMA UNMB MISF
           PERFORM READ-NEXT-A
           PERFORM READ-NEXT-B
           PERFORM UNTIL KA-REF = HIGH-VALUES AND KB-REF = HIGH-VALUES
               IF KA-REF < KB-REF
                   MOVE KA-REF TO CUR-REF
               ELSE
                   MOVE KB-REF TO CUR-REF
               END-IF
               PERFORM LOAD-GROUP
               PERFORM DUP-PHASE
               MOVE "W" TO PHASE
               PERFORM MATCH-PHASE
               PERFORM SPLIT-PHASE
               MOVE "A" TO PHASE
               PERFORM MATCH-PHASE
               MOVE "C" TO PHASE
               PERFORM MATCH-PHASE
               PERFORM WRITE-GROUP
           END-PERFORM
           PERFORM PRINT-TOTALS
           CLOSE LEDGA LEDGB MATCHF UNMA UNMB MISF
           STOP RUN.

       READ-NEXT-A.
           READ LEDGA INTO WS-A
               AT END MOVE HIGH-VALUES TO KA-REF
               NOT AT END
                   ADD 1 TO READ-A
                   MOVE PR-REF OF WS-A TO KA-REF
           END-READ.

       READ-NEXT-B.
           READ LEDGB INTO WS-B
               AT END MOVE HIGH-VALUES TO KB-REF
               NOT AT END
                   ADD 1 TO READ-B
                   MOVE PR-REF OF WS-B TO KB-REF
           END-READ.

       LOAD-GROUP.
           ADD 1 TO GROUPS
           MOVE 0 TO NA NB
           PERFORM UNTIL KA-REF NOT = CUR-REF
               ADD 1 TO NA
               IF NA > 50
                   DISPLAY "GROUP TOO BIG " CUR-REF
                   MOVE 16 TO RETURN-CODE
                   STOP RUN
               END-IF
               MOVE WS-A TO GA-REC(NA)
               COMPUTE GA-DAY(NA) =
                   FUNCTION INTEGER-OF-DATE(GA-DATE(NA))
               MOVE SPACE TO GA-ST(NA)
               MOVE 0 TO GA-WITH(NA)
               PERFORM READ-NEXT-A
           END-PERFORM
           PERFORM UNTIL KB-REF NOT = CUR-REF
               ADD 1 TO NB
               IF NB > 50
                   DISPLAY "GROUP TOO BIG " CUR-REF
                   MOVE 16 TO RETURN-CODE
                   STOP RUN
               END-IF
               MOVE WS-B TO GB-REC(NB)
               COMPUTE GB-DAY(NB) =
                   FUNCTION INTEGER-OF-DATE(GB-DATE(NB))
               MOVE SPACE TO GB-ST(NB)
               MOVE 0 TO GB-WITH(NB)
               PERFORM READ-NEXT-B
           END-PERFORM.

      * same amount + counterparty posted again later = duplicate
      * (row_number() > 1 in the sql)
       DUP-PHASE.
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > NA
               PERFORM VARYING J FROM 1 BY 1 UNTIL J > NA
                   IF J NOT = I AND GA-AMT(J) = GA-AMT(I)
                      AND GA-CPTY(J) = GA-CPTY(I)
                      AND (GA-DAY(J) < GA-DAY(I) OR
                          (GA-DAY(J) = GA-DAY(I) AND
                           GA-ID(J) < GA-ID(I)))
                       MOVE "D" TO GA-ST(I)
                   END-IF
               END-PERFORM
           END-PERFORM
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > NB
               PERFORM VARYING J FROM 1 BY 1 UNTIL J > NB
                   IF J NOT = I AND GB-AMT(J) = GB-AMT(I)
                      AND GB-CPTY(J) = GB-CPTY(I)
                      AND (GB-DAY(J) < GB-DAY(I) OR
                          (GB-DAY(J) = GB-DAY(I) AND
                           GB-ID(J) < GB-ID(I)))
                       MOVE "D" TO GB-ST(I)
                   END-IF
               END-PERFORM
           END-PERFORM.

      * is A(I) / B(J) a candidate for this step, sets K1 K2 sort keys
       CHECK-PAIR.
           MOVE "N" TO OK
           COMPUTE DD = GA-DAY(I) - GB-DAY(J)
           IF DD < 0
               COMPUTE DD = 0 - DD
           END-IF
           COMPUTE AD = GA-AMT(I) - GB-AMT(J)
           IF AD < 0
               COMPUTE AD = 0 - AD
           END-IF
           IF GA-ST(I) = SPACE AND GB-ST(J) = SPACE AND DD <= 3
               EVALUATE PHASE
                   WHEN "W"
                       IF GA-CPTY(I) = GB-CPTY(J)
                          AND GA-CCY(I) = GB-CCY(J) AND AD <= 0.02
                           MOVE "Y" TO OK
                           MOVE DD TO K1
                           MOVE AD TO K2
                       END-IF
                   WHEN "A"
                       IF GA-CPTY(I) = GB-CPTY(J)
                          AND GA-CCY(I) = GB-CCY(J) AND AD > 0.02
                           MOVE "Y" TO OK
                           MOVE AD TO K1
                           MOVE 0 TO K2
                       END-IF
                   WHEN "C"
                       IF GA-CPTY(I) NOT = GB-CPTY(J) AND AD <= 0.02
                           MOVE "Y" TO OK
                           MOVE DD TO K1
                           MOVE 0 TO K2
                       END-IF
               END-EVALUATE
           END-IF.

      * best B for every A, best A for every B, keep the mutual ones
       MATCH-PHASE.
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > NA
               MOVE 0 TO GA-BEST(I) BK1 BK2
               PERFORM VARYING J FROM 1 BY 1 UNTIL J > NB
                   PERFORM CHECK-PAIR
                   IF OK = "Y"
                       IF GA-BEST(I) = 0 OR K1 < BK1
                          OR (K1 = BK1 AND K2 < BK2)
                          OR (K1 = BK1 AND K2 = BK2
                              AND GB-ID(J) < BEST-ID)
                           MOVE J TO GA-BEST(I)
                           MOVE K1 TO BK1
                           MOVE K2 TO BK2
                           MOVE GB-ID(J) TO BEST-ID
                       END-IF
                   END-IF
               END-PERFORM
           END-PERFORM
           PERFORM VARYING J FROM 1 BY 1 UNTIL J > NB
               MOVE 0 TO GB-BEST(J) BK1 BK2
               PERFORM VARYING I FROM 1 BY 1 UNTIL I > NA
                   PERFORM CHECK-PAIR
                   IF OK = "Y"
                       IF GB-BEST(J) = 0 OR K1 < BK1
                          OR (K1 = BK1 AND K2 < BK2)
                          OR (K1 = BK1 AND K2 = BK2
                              AND GA-ID(I) < BEST-ID)
                           MOVE I TO GB-BEST(J)
                           MOVE K1 TO BK1
                           MOVE K2 TO BK2
                           MOVE GA-ID(I) TO BEST-ID
                       END-IF
                   END-IF
               END-PERFORM
           END-PERFORM
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > NA
               IF GA-BEST(I) > 0
                   MOVE GA-BEST(I) TO J
                   IF GB-BEST(J) = I
                       MOVE PHASE TO GA-ST(I) GB-ST(J)
                       MOVE J TO GA-WITH(I)
                       MOVE I TO GB-WITH(J)
                   END-IF
               END-IF
           END-PERFORM.

      * open bank lines of one counterparty, 2 or 3 of them within
      * 3 days, whose sum is one open erp record
       SPLIT-PHASE.
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > NA
               IF GA-ST(I) = SPACE
                   MOVE "Y" TO LEADER
                   PERFORM VARYING K FROM 1 BY 1 UNTIL K >= I
                       IF GA-ST(K) = SPACE
                          AND GA-CPTY(K) = GA-CPTY(I)
                          AND GA-CCY(K) = GA-CCY(I)
                           MOVE "N" TO LEADER
                       END-IF
                   END-PERFORM
                   IF LEADER = "Y"
                       PERFORM TRY-SPLIT
                   END-IF
               END-IF
           END-PERFORM.

       TRY-SPLIT.
           MOVE 0 TO CNT TOT
           MOVE GA-DAY(I) TO D1 D2
           PERFORM VARYING K FROM 1 BY 1 UNTIL K > NA
               IF GA-ST(K) = SPACE AND GA-CPTY(K) = GA-CPTY(I)
                  AND GA-CCY(K) = GA-CCY(I)
                   ADD 1 TO CNT
                   ADD GA-AMT(K) TO TOT
                   IF GA-DAY(K) < D1
                       MOVE GA-DAY(K) TO D1
                   END-IF
                   IF GA-DAY(K) > D2
                       MOVE GA-DAY(K) TO D2
                   END-IF
               END-IF
           END-PERFORM
           IF CNT >= 2 AND CNT <= 3 AND D2 - D1 <= 3
               MOVE 0 TO BEST-IX
               PERFORM VARYING J FROM 1 BY 1 UNTIL J > NB
                   COMPUTE AD = TOT - GB-AMT(J)
                   IF AD < 0
                       COMPUTE AD = 0 - AD
                   END-IF
                   IF GB-ST(J) = SPACE AND GB-CPTY(J) = GA-CPTY(I)
                      AND GB-CCY(J) = GA-CCY(I) AND AD <= 0.02
                      AND D2 - GB-DAY(J) <= 3
                      AND GB-DAY(J) - D1 <= 3
                       IF BEST-IX = 0 OR GB-ID(J) < BEST-ID
                           MOVE J TO BEST-IX
                           MOVE GB-ID(J) TO BEST-ID
                       END-IF
                   END-IF
               END-PERFORM
               IF BEST-IX > 0
                   MOVE "S" TO GB-ST(BEST-IX)
                   MOVE I TO GB-WITH(BEST-IX)
                   PERFORM VARYING K FROM 1 BY 1 UNTIL K > NA
                       IF GA-ST(K) = SPACE
                          AND GA-CPTY(K) = GA-CPTY(I)
                          AND GA-CCY(K) = GA-CCY(I)
                           MOVE "S" TO GA-ST(K)
                           MOVE BEST-IX TO GA-WITH(K)
                       END-IF
                   END-PERFORM
               END-IF
           END-IF.

      * anything still open is missing on the other side
       WRITE-GROUP.
           PERFORM VARYING I FROM 1 BY 1 UNTIL I > NA
               IF GA-ST(I) = SPACE
                   MOVE "M" TO GA-ST(I)
               END-IF
               EVALUATE GA-ST(I)
                   WHEN "W"
                   WHEN "S"
                       MOVE SPACES TO MATCH-REC
                       MOVE GA-ID(I) TO MR-A-ID
                       MOVE GA-WITH(I) TO J
                       MOVE GB-ID(J) TO MR-B-ID
                       MOVE GA-REF(I) TO MR-REF
                       MOVE GA-AMT(I) TO MR-AMOUNT
                       MOVE GA-DATE(I) TO MR-DATE
                       MOVE GA-ST(I) TO MR-RULE
                       WRITE MATCH-REC
                       ADD GA-AMT(I) TO AMT-MATCH
                       IF GA-ST(I) = "W"
                           ADD 1 TO CNT-WIN
                       ELSE
                           ADD 1 TO CNT-SPLA
                       END-IF
                   WHEN "D"
                   WHEN "M"
                       MOVE GA-ST(I) TO GA-RSN(I)
                       WRITE UNMA-REC FROM GA-REC(I)
                       ADD GA-AMT(I) TO AMT-UNMA
                       IF GA-ST(I) = "D"
                           ADD 1 TO CNT-DUPA
                       ELSE
                           ADD 1 TO CNT-MISSA
                       END-IF
                   WHEN OTHER
                       MOVE GA-ST(I) TO GA-RSN(I)
                       MOVE "A" TO MS-LEDGER
                       MOVE GA-REC(I) TO MS-DATA
                       WRITE MIS-REC
                       ADD 1 TO CNT-MISA
                       ADD GA-AMT(I) TO AMT-MIS
               END-EVALUATE
           END-PERFORM
           PERFORM VARYING J FROM 1 BY 1 UNTIL J > NB
               IF GB-ST(J) = SPACE
                   MOVE "M" TO GB-ST(J)
               END-IF
               EVALUATE GB-ST(J)
                   WHEN "W"
                       CONTINUE
                   WHEN "S"
                       ADD 1 TO CNT-SPLB
                   WHEN "D"
                   WHEN "M"
                       MOVE GB-ST(J) TO GB-RSN(J)
                       WRITE UNMB-REC FROM GB-REC(J)
                       ADD GB-AMT(J) TO AMT-UNMB
                       IF GB-ST(J) = "D"
                           ADD 1 TO CNT-DUPB
                       ELSE
                           ADD 1 TO CNT-MISSB
                       END-IF
                   WHEN OTHER
                       MOVE GB-ST(J) TO GB-RSN(J)
                       MOVE "B" TO MS-LEDGER
                       MOVE GB-REC(J) TO MS-DATA
                       WRITE MIS-REC
                       ADD 1 TO CNT-MISB
               END-EVALUATE
           END-PERFORM.

       PRINT-TOTALS.
           DISPLAY "RECON V2 TOTALS REPORT"
           DISPLAY "----------------------"
           MOVE READ-A TO OUT-CNT
           DISPLAY "RECORDS READ A        " OUT-CNT
           MOVE READ-B TO OUT-CNT
           DISPLAY "RECORDS READ B        " OUT-CNT
           MOVE GROUPS TO OUT-CNT
           DISPLAY "REFERENCE GROUPS      " OUT-CNT
           MOVE CNT-WIN TO OUT-CNT
           DISPLAY "MATCHED 1 TO 1        " OUT-CNT
           MOVE CNT-SPLA TO OUT-CNT
           DISPLAY "MATCHED SPLIT LINES   " OUT-CNT
           MOVE CNT-SPLB TO OUT-CNT
           DISPLAY "MATCHED SPLIT ERP     " OUT-CNT
           MOVE AMT-MATCH TO OUT-AMT
           DISPLAY "MATCHED AMOUNT A      " OUT-AMT
           MOVE CNT-DUPA TO OUT-CNT
           DISPLAY "UNMATCHED-A DUPLICATE " OUT-CNT
           MOVE CNT-MISSA TO OUT-CNT
           DISPLAY "UNMATCHED-A MISSING   " OUT-CNT
           MOVE AMT-UNMA TO OUT-AMT
           DISPLAY "UNMATCHED-A AMOUNT    " OUT-AMT
           MOVE CNT-DUPB TO OUT-CNT
           DISPLAY "UNMATCHED-B DUPLICATE " OUT-CNT
           MOVE CNT-MISSB TO OUT-CNT
           DISPLAY "UNMATCHED-B MISSING   " OUT-CNT
           MOVE AMT-UNMB TO OUT-AMT
           DISPLAY "UNMATCHED-B AMOUNT    " OUT-AMT
           MOVE CNT-MISA TO OUT-CNT
           DISPLAY "MISMATCH A SIDE       " OUT-CNT
           MOVE CNT-MISB TO OUT-CNT
           DISPLAY "MISMATCH B SIDE       " OUT-CNT
           MOVE AMT-MIS TO OUT-AMT
           DISPLAY "MISMATCH AMOUNT A     " OUT-AMT.
