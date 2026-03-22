package alert

import (
	"fmt"
	"net/smtp"
	"strings"

	"arclineit/arcline-uptime/internal/config"
)

type EmailAlerter struct {
	cfg config.AlertConfig
}

func NewEmailAlerter(cfg config.AlertConfig) *EmailAlerter {
	return &EmailAlerter{cfg: cfg}
}

// Send delivers an email via STARTTLS on the configured SMTP server.
// Port 587 with STARTTLS is expected; port 465 (SMTPS) is not supported.
func (e *EmailAlerter) Send(subject, body string) error {
	if len(e.cfg.To) == 0 {
		return fmt.Errorf("email alerter: no recipients configured")
	}

	auth := smtp.PlainAuth("", e.cfg.Username, e.cfg.Password, e.cfg.SMTPHost)
	toHeader := strings.Join(e.cfg.To, ", ")
	msg := fmt.Sprintf(
		"From: %s\r\nTo: %s\r\nSubject: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s",
		e.cfg.From, toHeader, subject, body,
	)
	addr := fmt.Sprintf("%s:%d", e.cfg.SMTPHost, e.cfg.SMTPPort)
	return smtp.SendMail(addr, auth, e.cfg.From, []string(e.cfg.To), []byte(msg))
}
