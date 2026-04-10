package cmd

import (
	"fmt"
	"math"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/lipgloss/table"
	"github.com/nickhudkins/mac-notify/ipc"
	"github.com/spf13/cobra"
)

var (
	clrCyan   = lipgloss.Color("6")
	clrYellow = lipgloss.Color("11")
	clrGreen  = lipgloss.Color("10")
)

var listCmd = &cobra.Command{
	Use:         "list",
	Aliases:     []string{"ls", "l"},
	Annotations: map[string]string{"group": "Messages:"},
	Short:       "List current notifications",
	RunE: func(cmd *cobra.Command, args []string) error {
		resp, err := ipc.Send(ipc.Request{Action: "list"})
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}
		if len(resp.Messages) == 0 {
			fmt.Println("No notifications")
			return nil
		}

		dim := lipgloss.NewStyle().Faint(true)

		var rows [][]string
		for _, m := range resp.Messages {
			msg := lipgloss.NewStyle().Foreground(clrCyan).Render(m.Text)

			source := dim.Render("—")
			if m.Source != "" {
				source = lipgloss.NewStyle().Foreground(clrYellow).Render(m.Source)
			}

			age := dim.Render(relativeTime(m.Time))

			id := dim.Render("—")
			if m.ID != "" {
				id = lipgloss.NewStyle().Foreground(clrGreen).Render(m.ID)
			}

			rows = append(rows, []string{msg, source, age, id})
		}

		t := table.New().
			Border(lipgloss.HiddenBorder()).
			Headers("MESSAGE", "SOURCE", "AGE", "ID").
			Rows(rows...).
			StyleFunc(func(row, col int) lipgloss.Style {
				s := lipgloss.NewStyle().PaddingRight(2)
				if row == table.HeaderRow {
					return s.Bold(true).Faint(true)
				}
				return s
			})

		fmt.Println(t)
		return nil
	},
}

func relativeTime(t time.Time) string {
	d := time.Since(t)
	switch {
	case d < time.Minute:
		return "just now"
	case d < time.Hour:
		return fmt.Sprintf("%dm ago", int(d.Minutes()))
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh ago", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd ago", int(math.Floor(d.Hours()/24)))
	}
}

func init() {
	rootCmd.AddCommand(listCmd)
}
