;;; Copyright 2020 Beckman Coulter, Inc.
;;;
;;; Permission is hereby granted, free of charge, to any person
;;; obtaining a copy of this software and associated documentation
;;; files (the "Software"), to deal in the Software without
;;; restriction, including without limitation the rights to use, copy,
;;; modify, merge, publish, distribute, sublicense, and/or sell copies
;;; of the Software, and to permit persons to whom the Software is
;;; furnished to do so, subject to the following conditions:
;;;
;;; The above copyright notice and this permission notice shall be
;;; included in all copies or substantial portions of the Software.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;;; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;;; WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;;; DEALINGS IN THE SOFTWARE.

#!chezscheme
(import
 (checkers)
 (chezscheme)
 (config)
 (config-params)
 (flycheck)
 (indent)
 (json)
 (keywords)
 (lsp)
 (software-info)
 (swish imports)
 (tower)
 (tower-client))

(define tower-port-number 51342)

(define cli
  (cli-specs
   default-help
   [doctor --doctor bool "check your system for potential problems"]
   [lsp --lsp bool "start Language Server Protocol mode"]
   [format --format (string "<format>")
     '("format specifiers that include the following"
       "substitution strings:"
       "%file, %type, %line, %column, %bfp, %efp, %msg")]
   [regexp-pass -r (list "<type>" "<regexp>")
     "report <regexp> matches as <type>={info|warning|error}"]
   [indent --indent bool "indent files (edit in-place)"]
   [tower --tower bool "start tower server"]
   [tower-db --tower-db (string "<filename>") "save tower database to <filename>"]
   [update-keywords --update-keywords bool "update keywords"]
   [user-config --user-config bool "load user configuration"]
   [verbose -v count "show debug messages (tower and indent only)"]
   [version --version bool "print version information"]
   [files (list . "file") "check file"]))

(software-info:install)
(let* ([opt (parse-command-line-arguments cli)]
       [files (or (opt 'files) '())])
  (define (regexp-opt->config)
    (let lp ([ls (or (opt 'regexp-pass) '())])
      (match ls
        [() '()]
        [(,type ,regexp . ,rest)
         (cons `(regexp ,type ,regexp) (lp rest))])))
  (cond
   [(opt 'help)
    (display-help (app:name) cli (opt))
    (exit 0)]
   [(opt 'version)
    (display (versions->string))
    (exit 0)]
   [(opt 'doctor)
    (config-output-port (console-output-port))
    (trace-output-port (console-output-port))
    (display (versions->string))
    (newline)
    (output-env)
    (config:load-user)
    (newline)
    (printf "Current directory: ~a\n" (cd))
    (let ()
      (define (find-repo dir)
        (if (file-exists? (path-combine dir ".git"))
            dir
            (let ([parent (path-parent dir)])
              (if (string=? parent dir)
                  #f
                  (find-repo parent)))))
      (let ([repo (find-repo (cd))])
        (cond
         [repo
          (printf "Nearest repository: ~a\n" repo)
          (newline)
          (config:load-project repo)]
         [else
          (printf "No repository found\n")])))
    (exit 0)]
   [(opt 'lsp)
    (config-output-port (console-error-port))
    (optional-checkers (make-optional-passes (regexp-opt->config)))
    (lsp:start-server tower-port-number (console-input-port) (console-output-port))]
   [(opt 'tower)
    (let ([verbose (opt 'verbose)]
          [tower-db (opt 'tower-db)])
      (cond
       [(not (tower:running? tower-port-number))
        (tower:start-server verbose tower-db tower-port-number)]
       [verbose
        (match-let* ([#(ok ,pid) (tower-client:start&link tower-port-number)])
          (unlink pid)
          (tower-client:shutdown-server)
          (kill pid 'shutdown))
        (let lp ([n 1])
          (receive (after 200 'ok))
          (cond
           [(not (tower:running? tower-port-number)) 'ok]
           [(< n 10) (lp (+ n 1))]
           [else (errorf #f "Tower is still running.")]))
        (tower:start-server verbose tower-db tower-port-number)]
       [else
        (errorf #f "Tower is already running.")]))]
   [(opt 'update-keywords)
    (let ([keywords
           (get-keywords
            (lambda (reason)
              (fprintf (console-error-port) "~a\n" (exit-reason->english reason))
              (flush-output-port (console-error-port))))])
      (match-let* ([#(ok ,pid) (tower-client:start&link tower-port-number)])
        (unlink pid)
        (tower-client:update-keywords keywords)))]
   [(and (opt 'indent) (not (null? files)))
    (let ([verbose (opt 'verbose)])
      (for-each
       (lambda (filename)
         (let* ([text (utf8->string (read-file filename))]
                [start (erlang:now)]
                [indented (indent text)]
                [end (erlang:now)])
           (cond
            [(string=? text indented)
             (printf "Unchanged")]
            [else
             (printf "Formatted")
             (let ([mode (get-mode filename)])
               (rename-path filename (string-append filename "~"))
               (let ([op (open-file-to-write filename)])
                 (on-exit (close-port op)
                   (display indented op)))
               (set-file-mode filename mode))])
           (when verbose
             (printf " ~6:D LOC ~4d ms"
               (let ([ip (open-input-string text)])
                 (let lp ([total 0])
                   (let ([x (get-char ip)])
                     (if (eof-object? x)
                         total
                         (lp (if (eq? x #\newline)
                                 (+ total 1)
                                 total))))))
               (- end start)))
           (printf " ~a\n" filename)
           ))
       files))]
   [(null? files)
    (display-help (app:name) cli (opt))
    (exit 0)]
   [else
    (optional-checkers (make-optional-passes (regexp-opt->config)))
    (when (opt 'user-config)
      (config:load-user))
    (report-format
     (compile-format
      (or (opt 'format) "%file: line %line: %msg")))
    (exit
     (fold-left
      (lambda (acc file)
        (max acc (flycheck:process-file file)))
      0
      files))]))
