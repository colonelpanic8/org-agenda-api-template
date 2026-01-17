;;; custom-config.el --- org-agenda-api configuration -*- lexical-binding: t -*-

;; This file is loaded by org-agenda-api to configure org-mode.
;; Your org files are synced to /data/org inside the container.
;;
;; For a more advanced setup with tangled dotfiles, see:
;; https://github.com/colonelpanic8/colonelpanic-org-agenda-api

;;; Code:

;; Set the org directory (where your org files are synced)
(setq org-directory "/data/org")

;; Include all .org files in the agenda
;; Modify this if you want to include only specific files
(setq org-agenda-files (directory-files-recursively org-directory "\\.org$"))

;; Example: Use specific files only
;; (setq org-agenda-files '("/data/org/todo.org" "/data/org/work.org"))

;; Example: Custom TODO keywords
;; (setq org-todo-keywords
;;       '((sequence "TODO(t)" "IN-PROGRESS(i)" "|" "DONE(d)" "CANCELLED(c)")))

;; Example: Custom agenda views
;; (setq org-agenda-custom-commands
;;       '(("n" "Next actions" todo "TODO")
;;         ("w" "Waiting" todo "WAITING")))

(provide 'custom-config)
;;; custom-config.el ends here
