;;; swish-mode.el --- Major mode for editing Swish Scheme programs   -*- lexical-binding: t; -*-

;;; Author: Lewis Kelley

;;; Commentary:

;; Overrides Emacs's default scheme indent with a custom one used by
;; Beckman Coulter Life Sciences for use on Swish and other projects.
;; Also adds miscellaneous keyword highlighting that Scheme mode
;; doesn't have.

;;; Package-Requires: (lsp-mode)

;;; Usage:

;; (require 'swish-mode)
;; (add-to-list 'auto-mode-alist '("\\.ss\\'" . swish-mode))
;; (add-to-list 'auto-mode-alist '("\\.ms\\'" . swish-mode))

;;; Code:

(require 'lsp-mode)
(require 'scheme)

(defgroup swish nil
  "Configuration details for `swish-mode'."
  :group 'editing)

(defun swish-indent-sexp ()
  "Indent each line of the sexp starting just after point."
  (interactive)
  (save-excursion
    (let ((start (point)))
      (forward-sexp 1)
      (lsp-format-region start (point))))
  ;; Move cursor to the start of the next sxp
  (forward-sexp 1)
  (backward-sexp 1))

(defun swish-indent-line ()
  "Indent current line as Scheme code."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (let ((start (point)))
      (end-of-line)
      (lsp-format-region start (point))))
  (skip-chars-forward " \t"))

(define-derived-mode swish-mode scheme-mode "swish"
  "Major mode for editing Swish files."

  (setq-local indent-line-function #'swish-indent-line))

(add-to-list 'lsp-language-id-configuration '(swish-mode . "swish"))

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection
                   '("swish-lint" "--lsp"))
  :major-modes '(swish-mode)
  :server-id 'swish-ls))

(add-hook 'swish-mode-hook #'lsp-mode)

(provide 'swish-mode)
;;; swish-mode.el ends here
