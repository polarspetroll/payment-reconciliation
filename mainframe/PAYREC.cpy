      * payment record, 100 bytes fixed (RECFM=FB LRECL=100)
           05 PR-ID              PIC X(10).
           05 PR-DATE            PIC X(8).
           05 PR-AMOUNT          PIC 9(11)V99.
           05 PR-CCY             PIC X(3).
           05 PR-CPTY            PIC X(40).
           05 PR-REF             PIC X(16).
           05 PR-SRC             PIC X(7).
      * reason code, only set on output records
           05 PR-REASON          PIC X.
           05 FILLER             PIC X(2).
