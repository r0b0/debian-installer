package main

/*
Opinionated Debian Installer
Copyright (C) 2022-2025 Robert T.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

import (
	"fmt"
	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

type Wizard struct {
	pageNames     []string
	forms         []*tview.Form
	pagesContents []tview.Primitive
	Footer        *tview.TextView
	pages         *tview.Pages
	currentPage   int
}

func NewWizard() Wizard {
	return Wizard{make([]string, 0),
		make([]*tview.Form, 0),
		make([]tview.Primitive, 0),
		tview.NewTextView().SetDynamicColors(true),
		nil,
		0}
}

func (w *Wizard) AddForm(name string, form *tview.Form) *Wizard {
	return w.AddPage(name, form, form)
}

func (w *Wizard) AddPage(name string, form *tview.Form, item tview.Primitive) *Wizard {
	w.pageNames = append(w.pageNames, name)
	w.forms = append(w.forms, form)
	w.pagesContents = append(w.pagesContents, item)
	return w
}

func (w *Wizard) MakePages() *tview.Pages {
	w.pages = tview.NewPages()
	for i := range w.forms {
		form := w.forms[i]
		item := w.pagesContents[i]

		visible := i == 0
		hasNext := i < len(w.forms)-1
		hasPrev := i > 0
		if hasPrev {
			form.AddButton("Back", func() {
				w.SwitchToPage(i - 1)
			})
		}
		if hasNext {
			form.AddButton("Next", func() {
				w.SwitchToPage(i + 1)
			})
		}
		w.pages.AddPage(w.pageNames[i], item, true, visible)
	}
	w.updateFooter()
	return w.pages
}

func (w *Wizard) SwitchToPage(i int) {
	w.currentPage = i
	w.pages.SwitchToPage(w.pageNames[i])
	w.updateFooter()
}

func (w *Wizard) updateFooter() {
	w.Footer.Clear()

	for i, name := range w.pageNames {
		var highlight string
		if i == w.currentPage {
			highlight = "[:red]"
		} else {
			highlight = ""
		}
		w.Footer.Write([]byte(fmt.Sprintf(" [:blue]F%d[-:-]%s %s [-:-] ", i+1, highlight, name)))
	}
}

func (w *Wizard) InputCapture(event *tcell.EventKey) *tcell.EventKey {
	fIndex := int(event.Key()) - int(tcell.KeyF1)
	if fIndex >= 0 && fIndex < len(w.pageNames) {
		w.SwitchToPage(fIndex)
		return nil
	} else {
		return event
	}
}
