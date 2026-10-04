(library (passgen)
  (export generate-password
          password-bits
          transform-outcomes
          transform-word
          random-below
          word-list)

  (import (chezscheme))

  (include "passgen/words.scm")

  ;; randomness ------------------------------------------------------------------

  ;; Chez's `random` is not suitable for secrets, so draw bytes from the OS
  (define urandom #f)

  (define (random-bytes n)
    (unless urandom
      (set! urandom (open-file-input-port "/dev/urandom")))
    (get-bytevector-n urandom n))

  ;; uniform integer in [0, n) using rejection sampling to avoid modulo bias
  (define (random-below n)
    (unless (and (fixnum? n) (< 0 n (expt 2 32)))
      (assertion-violation 'random-below "n must be in [1, 2^32)" n))
    (let* ([range (expt 2 32)]
           [limit (- range (mod range n))])
      (let loop ()
        (let ([x (bytevector-u32-ref (random-bytes 4) 0 (endianness little))])
          (if (< x limit) (mod x n) (loop))))))

  (define (random-element vec)
    (vector-ref vec (random-below (vector-length vec))))

  ;; word transformations ---------------------------------------------------------

  (define leet-table
    '((#\a . #\4) (#\e . #\3) (#\i . #\1) (#\o . #\0) (#\s . #\5) (#\t . #\7)))

  (define (reverse-word word)
    (list->string (reverse (string->list word))))

  ;; replace the letter at position i with its digit
  (define (leet-at word i)
    (let ([new (string-copy word)])
      (string-set! new i (cdr (assv (string-ref word i) leet-table)))
      new))

  ;; undo leet substitutions (each digit maps back to exactly one letter)
  (define (unleet token)
    (list->string
     (map (lambda (c)
            (let ([pair (find (lambda (p) (char=? (cdr p) c)) leet-table)])
              (if pair (car pair) c)))
          (string->list token))))

  ;; apply a step to every outcome; step maps a word to an alist of
  ;; (word . conditional-probability)
  (define (expand-outcomes outcomes step)
    (merge-outcomes
     (apply append
            (map (lambda (o)
                   (map (lambda (s) (cons (car s) (* (cdr o) (cdr s))))
                        (step (car o))))
                 outcomes))))

  ;; sum the probabilities of identical words (e.g., a reversed palindrome)
  (define (merge-outcomes outcomes)
    (let loop ([outcomes outcomes] [out '()])
      (if (null? outcomes)
          (reverse out)
          (let* ([w (caar outcomes)]
                 [same (filter (lambda (o) (string=? (car o) w)) outcomes)])
            (loop (remp (lambda (o) (string=? (car o) w)) outcomes)
                  (cons (cons w (apply + (map cdr same))) out))))))

  ;; Every word a base word can turn into, with its exact probability.
  ;; The transformations are applied in order, each independently:
  ;;   reverse (1/4):                       lips -> spil
  ;;   replace one letter with a digit (1/3): spil -> sp1l
  ;;   upcase if 4 letters or shorter (1/2):  sp1l -> SP1L
  (define (transform-outcomes word)
    (fold-left
     expand-outcomes
     (list (cons word 1))
     (list (lambda (w) (list (cons w 3/4) (cons (reverse-word w) 1/4)))
           (lambda (w)
             (let ([positions (filter (lambda (i) (assv (string-ref w i) leet-table))
                                      (iota (string-length w)))])
               (if (null? positions)
                   (list (cons w 1))
                   (cons (cons w 2/3)
                         (map (lambda (i)
                                (cons (leet-at w i) (/ 1/3 (length positions))))
                              positions)))))
           (lambda (w)
             (if (<= (string-length w) 4)
                 (list (cons w 1/2) (cons (string-upcase w) 1/2))
                 (list (cons w 1)))))))

  ;; sample one outcome exactly by drawing from the common denominator
  (define (transform-word word)
    (let* ([outcomes (transform-outcomes word)]
           [denom (apply lcm (map (lambda (o) (denominator (cdr o))) outcomes))]
           [r (/ (random-below denom) denom)])
      (let loop ([outcomes outcomes] [cum 0])
        (let ([cum (+ cum (cdar outcomes))])
          (if (or (< r cum) (null? (cdr outcomes)))
              (caar outcomes)
              (loop (cdr outcomes) cum))))))

  ;; entropy ----------------------------------------------------------------------

  (define word-set
    (let ([ht (make-hashtable string-hash string=?)])
      (vector-for-each (lambda (w) (hashtable-set! ht w #t)) word-list)
      ht))

  ;; probability that one draw (random word, then transform) yields token;
  ;; the only base words that can produce it are its unleeted, lowercased
  ;; form and that form reversed
  (define (token-probability token)
    (let* ([base (unleet (string-downcase token))]
           [candidates (if (string=? base (reverse-word base))
                           (list base)
                           (list base (reverse-word base)))])
      (apply +
             (map (lambda (w)
                    (if (hashtable-contains? word-set w)
                        (* (/ 1 (vector-length word-list))
                           (apply + (map cdr (filter (lambda (o) (string=? (car o) token))
                                                     (transform-outcomes w)))))
                        0))
                  candidates))))

  ;; Bits of entropy for an attacker who knows the word list and this scheme:
  ;; the sum over words of -log2(probability of drawing that word).
  ;; Ignores the (small) information in the word count and in rejecting
  ;; candidates without an uppercase letter or digit.
  (define (password-bits pw sep)
    (fold-left
     (lambda (bits token)
       (let ([p (token-probability token)])
         (when (zero? p)
           (assertion-violation 'password-bits "not a passgen password" pw))
         (- bits (log p 2))))
     0
     (split pw sep)))

  (define (split str sep)
    (let ([n (string-length str)]
          [k (string-length sep)])
      (let loop ([start 0] [i 0] [out '()])
        (cond [(> (+ i k) n)
               (reverse (cons (substring str start n) out))]
              [(string=? (substring str i (+ i k)) sep)
               (loop (+ i k) (+ i k) (cons (substring str start i) out))]
              [else (loop start (+ i 1) out)]))))

  ;; password assembly ------------------------------------------------------------

  (define (join strs sep)
    (if (null? strs)
        ""
        (fold-left (lambda (acc s) (string-append acc sep s)) (car strs) (cdr strs))))

  (define (has-char? pred str)
    (exists pred (string->list str)))

  (define min-words 3)

  ;; Builds one candidate: words are added until the password reaches a target
  ;; length drawn uniformly from [min-length, max-length].
  ;; Returns #f if the candidate overshoots max-length or has too few words.
  (define (make-password min-length max-length sep)
    (let ([target (+ min-length (random-below (+ 1 (- max-length min-length))))])
      (let loop ([words (list (transform-word (random-element word-list)))])
        (let ([pw (join words sep)])
          (cond [(> (string-length pw) max-length) #f]
                [(>= (string-length pw) target)
                 (and (>= (length words) min-words) pw)]
                [else (loop (cons (transform-word (random-element word-list))
                                  words))])))))

  ;; Generates candidates until one satisfies the length bounds, has at least
  ;; `min-words` words, an uppercase letter, a digit, and at least `min-bits`
  ;; bits of entropy (see password-bits).
  (define generate-password
    (case-lambda
      [() (generate-password 16 32 "-" 0)]
      [(min-length max-length sep min-bits)
       (unless (and (fixnum? min-length) (fixnum? max-length)
                    (<= 1 min-length max-length))
         (assertion-violation 'generate-password
                              "invalid length bounds" min-length max-length))
       ;; words are a-z, so a separator without letters or digits keeps
       ;; passwords unambiguous to split
       (unless (and (string? sep)
                    (> (string-length sep) 0)
                    (not (exists char-alphabetic? (string->list sep)))
                    (not (exists char-numeric? (string->list sep))))
         (assertion-violation 'generate-password
                              "separator must be non-empty with no letters or digits" sep))
       (let loop ([attempts 0])
         (when (> attempts 100000)
           (error 'generate-password
                  "could not satisfy constraints; try relaxing them"))
         (let ([pw (make-password min-length max-length sep)])
           (if (and pw
                    (has-char? char-upper-case? pw)
                    (has-char? char-numeric? pw)
                    (>= (password-bits pw sep) min-bits))
               pw
               (loop (+ attempts 1)))))]))

  )
